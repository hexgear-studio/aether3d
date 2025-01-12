#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>
#include <string.h>
#include <unordered_map>
#include <vector>
#include "GfxDevice.hpp"
#include "LightTiler.hpp"
#include "Renderer.hpp"
#include "RenderTexture.hpp"
#include "Shader.hpp"
#include "System.hpp"
#include "Statistics.hpp"
#include "Texture2D.hpp"
#include "TextureCube.hpp"
#include "VertexBuffer.hpp"
#if !TARGET_OS_IPHONE
#include "Window.hpp"
#else
namespace ae3d
{
    namespace Window
    {
        void GetSize( int& outWidth, int& outHeight );
    }
}
#endif

float GetFloatAnisotropy( ae3d::Anisotropy anisotropy );
extern ae3d::Renderer renderer;

constexpr int UboCount = 2400;
id <MTLDevice> device;
id <MTLCommandQueue> commandQueue;
id <MTLLibrary> defaultLibrary;
id <MTLDepthStencilState> depthStateLessEqualWriteOn;
id <MTLDepthStencilState> depthStateLessEqualWriteOff;
id <MTLDepthStencilState> depthStateNoneWriteOff;
MTKView* view;
extern int tex2dMemoryUsage;

MTLRenderPassDescriptor* renderPassDescriptorApp = nullptr;
MTLRenderPassDescriptor* renderPassDescriptorFBO = nullptr;
id<MTLRenderCommandEncoder> renderEncoder;
id<MTLCommandBuffer> commandBuffer;
id<MTLTexture> textures[ 13 ];
id<MTLTexture> msaaColorTarget;
id<MTLTexture> msaaDepthTarget;

// TODO: Move somewhere else.
void PlatformInitGamePad()
{
}

enum SamplerIndexByAnisotropy : int
{
    One = 0,
    Two,
    Four,
    Eight
};

int GetSamplerIndexByAnisotropy( ae3d::Anisotropy anisotropy )
{
    const float floatAnisotropy = GetFloatAnisotropy( anisotropy );
    
    if (floatAnisotropy == 1)
    {
        return SamplerIndexByAnisotropy::One;
    }
    if (floatAnisotropy == 2)
    {
        return SamplerIndexByAnisotropy::Two;
    }
    if (floatAnisotropy == 4)
    {
        return SamplerIndexByAnisotropy::Four;
    }
    if (floatAnisotropy == 8)
    {
        return SamplerIndexByAnisotropy::Eight;
    }

    return SamplerIndexByAnisotropy::One;
}

namespace ae3d
{
    namespace GfxDevice
    {
        unsigned backBufferWidth;
        unsigned backBufferHeight;
    }
}

namespace GfxDeviceGlobal
{
    int sampleCount = 1;
    bool isRenderingToTexture = false;
    ae3d::GfxDevice::ClearFlags clearFlags = ae3d::GfxDevice::ClearFlags::Depth;
    std::unordered_map< std::uint64_t, id <MTLRenderPipelineState> > psoCache;
    id<MTLSamplerState> samplerStates[ 13 ];
    id<MTLBuffer> uniformBuffers[ UboCount ];
    int currentUboIndex;
    ae3d::DataType currentRenderTargetDataType = ae3d::DataType::UByte;
    ae3d::LightTiler lightTiler;
    std::vector< ae3d::VertexBuffer > lineBuffers;
    int viewport[ 4 ];
    MTLScissorRect scissor;
    unsigned frameIndex = 0;
    ae3d::VertexBuffer uiBuffer;
    ae3d::VertexBuffer uiBuffer2;
    PerObjectUboStruct perObjectUboStruct;
    id <MTLRenderPipelineState> cachedPSO;
    
    struct Samplers
    {
        id<MTLSamplerState> linearRepeat;
        id<MTLSamplerState> linearClamp;
        id<MTLSamplerState> pointRepeat;
        id<MTLSamplerState> pointClamp;
    } samplers[ 5 ];
    
    void CreateSamplers()
    {
        for (int samplerIndex = 0; samplerIndex < 4; ++samplerIndex)
        {
            MTLSamplerDescriptor *samplerDescriptor = [MTLSamplerDescriptor new];

            samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
            samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
            samplerDescriptor.mipFilter = MTLSamplerMipFilterLinear;
            samplerDescriptor.sAddressMode = MTLSamplerAddressModeRepeat;
            samplerDescriptor.tAddressMode = MTLSamplerAddressModeRepeat;
            samplerDescriptor.rAddressMode = MTLSamplerAddressModeRepeat;
            samplerDescriptor.maxAnisotropy = (NSUInteger)std::pow( 2, samplerIndex );
            samplerDescriptor.label = @"linear repeat";
            samplers[ samplerIndex ].linearRepeat = [device newSamplerStateWithDescriptor:samplerDescriptor];

            samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
            samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
            samplerDescriptor.mipFilter = MTLSamplerMipFilterLinear;
            samplerDescriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
            samplerDescriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
            samplerDescriptor.rAddressMode = MTLSamplerAddressModeClampToEdge;
            samplerDescriptor.maxAnisotropy = (NSUInteger)std::pow( 2, samplerIndex );
            samplerDescriptor.label = @"linear clamp";
            samplers[ samplerIndex ].linearClamp = [device newSamplerStateWithDescriptor:samplerDescriptor];

            samplerDescriptor.minFilter = MTLSamplerMinMagFilterNearest;
            samplerDescriptor.magFilter = MTLSamplerMinMagFilterNearest;
            samplerDescriptor.mipFilter = MTLSamplerMipFilterNearest;
            samplerDescriptor.sAddressMode = MTLSamplerAddressModeRepeat;
            samplerDescriptor.tAddressMode = MTLSamplerAddressModeRepeat;
            samplerDescriptor.rAddressMode = MTLSamplerAddressModeRepeat;
            samplerDescriptor.maxAnisotropy = (NSUInteger)std::pow( 2, samplerIndex );
            samplerDescriptor.label = @"point repeat";
            samplers[ samplerIndex ].pointRepeat = [device newSamplerStateWithDescriptor:samplerDescriptor];

            samplerDescriptor.minFilter = MTLSamplerMinMagFilterNearest;
            samplerDescriptor.magFilter = MTLSamplerMinMagFilterNearest;
            samplerDescriptor.mipFilter = MTLSamplerMipFilterNearest;
            samplerDescriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
            samplerDescriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
            samplerDescriptor.rAddressMode = MTLSamplerAddressModeClampToEdge;
            samplerDescriptor.maxAnisotropy = (NSUInteger)std::pow( 2, samplerIndex );
            samplerDescriptor.label = @"point clamp";
            samplers[ samplerIndex ].pointClamp = [device newSamplerStateWithDescriptor:samplerDescriptor];
        }

        for (int slot = 0; slot < 13; ++slot)
        {
            samplerStates[ slot ] = samplers[ SamplerIndexByAnisotropy::One ].pointClamp;
        }
    }
    
    void SetSampler( int textureUnit, ae3d::TextureFilter filter, ae3d::TextureWrap wrap, ae3d::Anisotropy anisotropy )
    {
        if (textureUnit > 12)
        {
            ae3d::System::Print( "Trying to set a sampler with too high index %d\n", textureUnit );
            return;
        }
        
        if (filter == ae3d::TextureFilter::Nearest && wrap == ae3d::TextureWrap::Clamp)
        {
            samplerStates[ textureUnit ] = samplers[ GetSamplerIndexByAnisotropy( anisotropy ) ].pointClamp;
        }
        else if (filter == ae3d::TextureFilter::Nearest && wrap == ae3d::TextureWrap::Repeat)
        {
            samplerStates[ textureUnit ] = samplers[ GetSamplerIndexByAnisotropy( anisotropy ) ].pointRepeat;
        }
        else if (filter == ae3d::TextureFilter::Linear && wrap == ae3d::TextureWrap::Clamp)
        {
            samplerStates[ textureUnit ] = samplers[ GetSamplerIndexByAnisotropy( anisotropy ) ].linearClamp;
        }
        else if (filter == ae3d::TextureFilter::Linear && wrap == ae3d::TextureWrap::Repeat)
        {
            samplerStates[ textureUnit ] = samplers[ GetSamplerIndexByAnisotropy( anisotropy ) ].linearRepeat;
        }
        else
        {
            ae3d::System::Assert( false, "unhandled texture state" );
        }
    }
}

void UploadPerObjectUbo()
{
    id<MTLBuffer> uniformBuffer = ae3d::GfxDevice::GetCurrentUniformBuffer();
    uint8_t* bufferPointer = (uint8_t *)[uniformBuffer contents];

    memcpy( bufferPointer, &GfxDeviceGlobal::perObjectUboStruct, sizeof( GfxDeviceGlobal::perObjectUboStruct ) );
#if !TARGET_OS_IPHONE
    [uniformBuffer didModifyRange:NSMakeRange( 0, sizeof( GfxDeviceGlobal::perObjectUboStruct ) )];
#endif
}

namespace ae3d
{
    namespace System
    {
        namespace Statistics
        {
            void GetStatistics( char* outStr )
            {
                std::string str( "frame time: " );
                str += std::to_string( ::Statistics::GetFrameTimeMS() );
                str += "\nshadow map time: ";
                str += std::to_string( ::Statistics::GetShadowMapTimeMS() );
                str += "\ndepth pass time: ";
                str += std::to_string( ::Statistics::GetDepthNormalsTimeMS() );
                str += "\nbloom time CPU: ";
                str += std::to_string( ::Statistics::GetBloomCpuTimeMS());
                str += "\ndraw calls: ";
                str += std::to_string( ::Statistics::GetDrawCalls() );
                str += "\nscene AABB: ";
                str += std::to_string( ::Statistics::GetSceneAABBTimeMS() );
                str += "\nfrustum cull: ";
                str += std::to_string( ::Statistics::GetFrustumCullTimeMS() );
                str += "\nmemory: ";
                str += std::to_string([device currentAllocatedSize] / (1024 * 1024));
                str += " MiB";
                str += "\nlight update time: ";
                str += std::to_string( ::Statistics::GetLightUpdateTimeMS() );
                str += "\ntextures: ";
                str += std::to_string(tex2dMemoryUsage / (1024 * 1024));
                str += " MiB\n";
                std::strcpy( outStr, str.c_str() );
            }
        }
    }
}

namespace
{
    float clearColor[] = { 0, 0, 0, 0 };
}

void ae3d::GfxDevice::GetNewUniformBuffer()
{
    GfxDeviceGlobal::currentUboIndex = (GfxDeviceGlobal::currentUboIndex + 1) % UboCount;
}

id <MTLBuffer> ae3d::GfxDevice::GetCurrentUniformBuffer()
{
    return GfxDeviceGlobal::uniformBuffers[ GfxDeviceGlobal::currentUboIndex ];
}

void ae3d::GfxDevice::DrawUI( int scX, int scY, int scWidth, int scHeight, int elemCount, int offset )
{
    int scissor[ 4 ] = { scX, scY, scWidth, scHeight };
    SetScissor( scissor );
    Draw( GfxDeviceGlobal::frameIndex % 2 == 0 ? GfxDeviceGlobal::uiBuffer : GfxDeviceGlobal::uiBuffer2, offset, offset + elemCount, renderer.builtinShaders.uiShader, BlendMode::AlphaBlend, DepthFunc::NoneWriteOff, CullMode::Off, FillMode::Solid, GfxDevice::PrimitiveTopology::Triangles );
}

void ae3d::GfxDevice::MapUIVertexBuffer( int vertexSize, int indexSize, void** outMappedVertices, void** outMappedIndices )
{
    System::Assert( [GfxDeviceGlobal::uiBuffer.GetVertexBuffer() contents] != nullptr, "vertices are null" );
    System::Assert( [GfxDeviceGlobal::uiBuffer.GetIndexBuffer() contents] != nullptr, "indices are null" );
    
    if (GfxDeviceGlobal::frameIndex % 2 == 0)
    {
        *outMappedVertices = (void*)[GfxDeviceGlobal::uiBuffer.GetVertexBuffer() contents];
        *outMappedIndices = (void*)[GfxDeviceGlobal::uiBuffer.GetIndexBuffer() contents];
    }
    else
    {
        *outMappedVertices = (void*)[GfxDeviceGlobal::uiBuffer2.GetVertexBuffer() contents];
        *outMappedIndices = (void*)[GfxDeviceGlobal::uiBuffer2.GetIndexBuffer() contents];
    }
}

void ae3d::GfxDevice::UnmapUIVertexBuffer()
{
}

void ae3d::GfxDevice::BeginDepthNormalsGpuQuery()
{
    // TODO: Implement
}

void ae3d::GfxDevice::EndDepthNormalsGpuQuery()
{
    // TODO: Implement
}

void ae3d::GfxDevice::BeginShadowMapGpuQuery()
{
    // TODO: Implement
}

void ae3d::GfxDevice::EndShadowMapGpuQuery()
{
    // TODO: Implement
}

void ae3d::GfxDevice::SetPolygonOffset( bool enable, float factor, float units )
{
}

void ae3d::GfxDevice::SetViewport( int viewport[ 4 ] )
{
    GfxDeviceGlobal::viewport[ 0 ] = viewport[ 0 ];
    GfxDeviceGlobal::viewport[ 1 ] = viewport[ 1 ];
    GfxDeviceGlobal::viewport[ 2 ] = viewport[ 2 ];
    GfxDeviceGlobal::viewport[ 3 ] = viewport[ 3 ];
}

void ae3d::GfxDevice::SetScissor( int scissor[ 4 ] )
{
    GfxDeviceGlobal::scissor.x = scissor[ 0 ];
    GfxDeviceGlobal::scissor.y = scissor[ 1 ];
    GfxDeviceGlobal::scissor.width = scissor[ 2 ];
    GfxDeviceGlobal::scissor.height = scissor[ 3 ];
}

void ae3d::GfxDevice::Init( int width, int height )
{
    GfxDevice::backBufferWidth = width;
    GfxDevice::backBufferHeight = height;
}

void ae3d::GfxDevice::SetCurrentDrawableMetal( MTKView* aView )
{
    view = aView;
}

void ae3d::GfxDevice::PushGroupMarker( const char* name )
{
    NSString* fName = [NSString stringWithUTF8String: name];
    [renderEncoder pushDebugGroup:fName];
}

void ae3d::GfxDevice::PopGroupMarker()
{
    [renderEncoder popDebugGroup];
}

void ae3d::Window::GetSize( int& outWidth, int& outHeight )
{
    outWidth = GfxDevice::backBufferWidth / 2;
    outHeight = GfxDevice::backBufferHeight / 2;
}

void ae3d::GfxDevice::InitMetal( id <MTLDevice> metalDevice, MTKView* aView, int sampleCount, int uiVBSize, int uiIBSize )
{
    if (sampleCount < 1 || sampleCount > 8)
    {
        sampleCount = 1;
    }
    
    renderer.GenerateSSAOKernel( 16, GfxDeviceGlobal::perObjectUboStruct.kernelOffsets );
    GfxDeviceGlobal::perObjectUboStruct.kernelSize = 16;
    GfxDeviceGlobal::perObjectUboStruct.windowWidth = aView.bounds.size.width * 2;
    GfxDeviceGlobal::perObjectUboStruct.windowHeight = aView.bounds.size.height * 2;

    device = metalDevice;

    commandQueue = [device newCommandQueue];
    defaultLibrary = [device newDefaultLibrary];

    renderPassDescriptorFBO = [MTLRenderPassDescriptor renderPassDescriptor];

    GfxDevice::backBufferWidth = aView.bounds.size.width * 2;
    GfxDevice::backBufferHeight = aView.bounds.size.height * 2;
    GfxDeviceGlobal::sampleCount = sampleCount;
    
    for (std::size_t uboIndex = 0; uboIndex < UboCount; ++uboIndex)
    {
#if !TARGET_OS_IPHONE
        GfxDeviceGlobal::uniformBuffers[ uboIndex ] = [GfxDevice::GetMetalDevice() newBufferWithLength:UNIFORM_BUFFER_SIZE options:MTLResourceStorageModeManaged];
#else
        GfxDeviceGlobal::uniformBuffers[ uboIndex ] = [GfxDevice::GetMetalDevice() newBufferWithLength:UNIFORM_BUFFER_SIZE options:MTLResourceCPUCacheModeDefaultCache];
#endif
        GfxDeviceGlobal::uniformBuffers[ uboIndex ].label = @"uniform buffer";
    }
    
    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLessEqual;
    depthStateDesc.depthWriteEnabled = YES;
    depthStateDesc.label = @"lessEqual write on";
    depthStateLessEqualWriteOn = [device newDepthStencilStateWithDescriptor:depthStateDesc];

    depthStateDesc.depthCompareFunction = MTLCompareFunctionLessEqual;
    depthStateDesc.depthWriteEnabled = NO;
    depthStateDesc.label = @"lessEqual write off";
    depthStateLessEqualWriteOff = [device newDepthStencilStateWithDescriptor:depthStateDesc];

    depthStateDesc.depthCompareFunction = MTLCompareFunctionAlways;
    depthStateDesc.depthWriteEnabled = NO;
    depthStateDesc.label = @"none write off";
    depthStateNoneWriteOff = [device newDepthStencilStateWithDescriptor:depthStateDesc];

    GfxDeviceGlobal::CreateSamplers();
    GfxDeviceGlobal::lightTiler.Init();

    Array< VertexBuffer::VertexPTC > vertices( uiVBSize );
    Array< VertexBuffer::Face > faces( uiIBSize );
    GfxDeviceGlobal::uiBuffer.Generate( faces.elements, int( faces.count ), vertices.elements, int( vertices.count ), VertexBuffer::Storage::CPU );
    GfxDeviceGlobal::uiBuffer2.Generate( faces.elements, int( faces.count ), vertices.elements, int( vertices.count ), VertexBuffer::Storage::CPU );

    if (sampleCount == 1)
    {
        return;
    }
    
    MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:aView.colorPixelFormat
                                                                                        width:GfxDevice::backBufferWidth
                                                                                       height:GfxDevice::backBufferHeight
                                                                                    mipmapped:NO];
        
    desc.textureType = MTLTextureType2DMultisample;
    desc.sampleCount = sampleCount;
    desc.resourceOptions = MTLResourceStorageModePrivate;
    desc.usage = MTLTextureUsageRenderTarget;
    
    msaaColorTarget = [device newTextureWithDescriptor:desc];
    msaaColorTarget.label = @"MSAA Color Target";
    
    MTLTextureDescriptor* depthDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                    width:GfxDevice::backBufferWidth
                                                                                   height:GfxDevice::backBufferHeight
                                                                                mipmapped:NO];

    depthDesc.textureType = MTLTextureType2DMultisample;
    depthDesc.sampleCount = sampleCount;
    depthDesc.resourceOptions = MTLResourceStorageModePrivate;
    depthDesc.usage = MTLTextureUsageRenderTarget;
    
    msaaDepthTarget = [device newTextureWithDescriptor:depthDesc];
    msaaDepthTarget.label = @"MSAA Depth Target";
}

id <MTLDevice> ae3d::GfxDevice::GetMetalDevice()
{
    return device;
}

id <MTLLibrary> ae3d::GfxDevice::GetDefaultMetalShaderLibrary()
{
    return defaultLibrary;
}

void ae3d::GfxDevice::GetGpuMemoryUsage( unsigned& outGpuUsageMBytes, unsigned& outGpuBudgetMBytes )
{
    outGpuUsageMBytes = 0;
    outGpuBudgetMBytes = 0;
}

void ae3d::GfxDevice::ClearScreen( unsigned clearFlags )
{
    GfxDeviceGlobal::clearFlags = (ae3d::GfxDevice::ClearFlags)clearFlags;
}

std::uint64_t GetPSOHash( ae3d::Shader& shader, ae3d::GfxDevice::BlendMode blendMode, ae3d::GfxDevice::DepthFunc depthFunc,
                       ae3d::VertexBuffer::VertexFormat vertexFormat, ae3d::DataType pixelFormat,
                       MTLPixelFormat depthFormat, int sampleCount, ae3d::GfxDevice::PrimitiveTopology topology )
{
    std::uint64_t outResult = (ptrdiff_t)&shader.vertexProgram;
    outResult += (ptrdiff_t)&shader.fragmentProgram;
    outResult += (unsigned)blendMode;
    outResult += ((unsigned)depthFunc) * 2;
    outResult += ((unsigned)vertexFormat) * 4;
    outResult += ((unsigned)pixelFormat) * 8;
    outResult += ((unsigned)depthFormat) * 16;
    outResult += sampleCount * 32;
    outResult += ((unsigned)topology) * 64;
    
    return outResult;
}

id <MTLRenderPipelineState> GetPSO( ae3d::Shader& shader, ae3d::GfxDevice::BlendMode blendMode,
                                    ae3d::VertexBuffer::VertexFormat vertexFormat, ae3d::DataType pixelFormat,
                                   MTLPixelFormat depthFormat, int sampleCount, ae3d::GfxDevice::PrimitiveTopology topology )
{
    const std::uint64_t psoHash = GetPSOHash( shader, blendMode, /* unused on Metal*/ ae3d::GfxDevice::DepthFunc::LessOrEqualWriteOn, vertexFormat, pixelFormat, depthFormat, sampleCount, topology );

    if (GfxDeviceGlobal::psoCache.find( psoHash ) == std::end( GfxDeviceGlobal::psoCache ))
    {
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.sampleCount = sampleCount;
        pipelineStateDescriptor.vertexFunction = shader.vertexProgram;
        pipelineStateDescriptor.fragmentFunction = shader.fragmentProgram;
#if !TARGET_OS_IPHONE
        pipelineStateDescriptor.inputPrimitiveTopology = (topology == ae3d::GfxDevice::PrimitiveTopology::Triangles) ?
        MTLPrimitiveTopologyClassTriangle : MTLPrimitiveTopologyClassLine;
#endif
        MTLPixelFormat format = MTLPixelFormatBGRA8Unorm_sRGB;

        if (pixelFormat == ae3d::DataType::R32G32)
        {
            format = MTLPixelFormatRG32Float;
        }
        else if (pixelFormat == ae3d::DataType::Float)
        {
            format = MTLPixelFormatRGBA32Float;
        }
        else if (pixelFormat == ae3d::DataType::Float16)
        {
            format = MTLPixelFormatRGBA16Float;
        }

        pipelineStateDescriptor.colorAttachments[0].pixelFormat = format;
        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = blendMode != ae3d::GfxDevice::BlendMode::Off;
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = blendMode == ae3d::GfxDevice::BlendMode::AlphaBlend ?  MTLBlendFactorSourceAlpha : MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = blendMode == ae3d::GfxDevice::BlendMode::AlphaBlend ?  MTLBlendFactorOneMinusSourceAlpha : MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.depthAttachmentPixelFormat = depthFormat;

        MTLVertexDescriptor* vertexDesc = [MTLVertexDescriptor vertexDescriptor];
        
        if (vertexFormat == ae3d::VertexBuffer::VertexFormat::PTNTC)
        {
            pipelineStateDescriptor.label = @"pipeline PTNTC";

            // Position
            vertexDesc.attributes[0].format = MTLVertexFormatFloat3;
            vertexDesc.attributes[0].bufferIndex = 0;
            vertexDesc.attributes[0].offset = 0;
            
            // Texcoord
            vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
            vertexDesc.attributes[1].bufferIndex = 0;
            vertexDesc.attributes[1].offset = 4 * 3;

            // Normal
            vertexDesc.attributes[3].format = MTLVertexFormatFloat3;
            vertexDesc.attributes[3].bufferIndex = 0;
            vertexDesc.attributes[3].offset = 4 * 5;

            // Tangent
            vertexDesc.attributes[4].format = MTLVertexFormatFloat4;
            vertexDesc.attributes[4].bufferIndex = 0;
            vertexDesc.attributes[4].offset = 4 * 8;

            // Color
            vertexDesc.attributes[2].format = MTLVertexFormatFloat4;
            vertexDesc.attributes[2].bufferIndex = 0;
            vertexDesc.attributes[2].offset = 4 * 12;

            vertexDesc.layouts[0].stride = sizeof( ae3d::VertexBuffer::VertexPTNTC );
            vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
        }
        else if (vertexFormat == ae3d::VertexBuffer::VertexFormat::PTNTC_Skinned)
        {
            pipelineStateDescriptor.label = @"pipeline PTNTC_Skinned";
            
            // Position
            vertexDesc.attributes[0].format = MTLVertexFormatFloat3;
            vertexDesc.attributes[0].bufferIndex = 0;
            vertexDesc.attributes[0].offset = 0;
            
            // Texcoord
            vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
            vertexDesc.attributes[1].bufferIndex = 0;
            vertexDesc.attributes[1].offset = 4 * 3;
            
            // Normal
            vertexDesc.attributes[3].format = MTLVertexFormatFloat3;
            vertexDesc.attributes[3].bufferIndex = 0;
            vertexDesc.attributes[3].offset = 4 * 5;
            
            // Tangent
            vertexDesc.attributes[4].format = MTLVertexFormatFloat4;
            vertexDesc.attributes[4].bufferIndex = 0;
            vertexDesc.attributes[4].offset = 4 * 8;
            
            // Color
            vertexDesc.attributes[2].format = MTLVertexFormatFloat4;
            vertexDesc.attributes[2].bufferIndex = 0;
            vertexDesc.attributes[2].offset = 4 * 12;
            
            // Weights
            vertexDesc.attributes[ ae3d::VertexBuffer::weightChannel ].format = MTLVertexFormatFloat4;
            vertexDesc.attributes[ ae3d::VertexBuffer::weightChannel ].bufferIndex = 0;
            vertexDesc.attributes[ ae3d::VertexBuffer::weightChannel ].offset = 4 * 16;

            // Bones
            vertexDesc.attributes[ ae3d::VertexBuffer::boneChannel ].format = MTLVertexFormatInt4;
            vertexDesc.attributes[ ae3d::VertexBuffer::boneChannel ].bufferIndex = 0;
            vertexDesc.attributes[ ae3d::VertexBuffer::boneChannel ].offset = 4 * 20;

            vertexDesc.layouts[0].stride = sizeof( ae3d::VertexBuffer::VertexPTNTC_Skinned );
            vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
        }
        else if (vertexFormat == ae3d::VertexBuffer::VertexFormat::PTN)
        {
            pipelineStateDescriptor.label = @"pipeline PTN";
            
            // Position
            vertexDesc.attributes[0].format = MTLVertexFormatFloat3;
            vertexDesc.attributes[0].bufferIndex = 0;
            vertexDesc.attributes[0].offset = 0;
            
            // Texcoord
            vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
            vertexDesc.attributes[1].bufferIndex = 0;
            vertexDesc.attributes[1].offset = 4 * 3;

            // Color
            vertexDesc.attributes[2].format = MTLVertexFormatFloat4;
            vertexDesc.attributes[2].bufferIndex = 1;
            vertexDesc.attributes[2].offset = 0;

            // Normal
            vertexDesc.attributes[3].format = MTLVertexFormatFloat3;
            vertexDesc.attributes[3].bufferIndex = 0;
            vertexDesc.attributes[3].offset = 4 * 5;
            
            vertexDesc.layouts[0].stride = sizeof( ae3d::VertexBuffer::VertexPTN );
            vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

            vertexDesc.layouts[1].stride = 4 * 4;
            vertexDesc.layouts[1].stepFunction = MTLVertexStepFunctionPerVertex;
        }
        else if (vertexFormat == ae3d::VertexBuffer::VertexFormat::PTC)
        {
            pipelineStateDescriptor.label = @"pipeline PTC";
            
            // Position
            vertexDesc.attributes[0].format = MTLVertexFormatFloat3;
            vertexDesc.attributes[0].bufferIndex = 0;
            vertexDesc.attributes[0].offset = 0;
            
            // Texcoord
            vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
            vertexDesc.attributes[1].bufferIndex = 0;
            vertexDesc.attributes[1].offset = 4 * 3;
            
            // Color
            vertexDesc.attributes[2].format = MTLVertexFormatFloat4;
            vertexDesc.attributes[2].bufferIndex = 0;
            vertexDesc.attributes[2].offset = 4 * 5;
            
            // Normal
            vertexDesc.attributes[3].format = MTLVertexFormatFloat3;
            vertexDesc.attributes[3].bufferIndex = 1;
            vertexDesc.attributes[3].offset = 0;
            
            vertexDesc.layouts[0].stride = sizeof( ae3d::VertexBuffer::VertexPTC );
            vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
            
            vertexDesc.layouts[1].stride = 3 * 4;
            vertexDesc.layouts[1].stepFunction = MTLVertexStepFunctionPerVertex;
        }
        else
        {
            //ae3d::System::Assert( false, "unimplemented vertex format" );
        }
        
        pipelineStateDescriptor.vertexDescriptor = vertexDesc;
        
        NSError* error = NULL;
        MTLRenderPipelineReflection* reflectionObj;
        MTLPipelineOption option = MTLPipelineOptionBufferTypeInfo | MTLPipelineOptionArgumentInfo;
        id <MTLRenderPipelineState> pso = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor options:option reflection:&reflectionObj error:&error];
        
        if (!pso)
        {
            NSLog(@"Failed to create pipeline state, error %@", error);
        }

        GfxDeviceGlobal::psoCache[ psoHash ] = pso;
        
        shader.LoadUniforms( reflectionObj );        
    }

    return GfxDeviceGlobal::psoCache[ psoHash ];
}

void ae3d::GfxDevice::DrawLines( int handle, Shader& shader )
{
    if (handle < 0 || handle >= int( GfxDeviceGlobal::lineBuffers.size() ))
    {
        return;
    }
    
    Draw( GfxDeviceGlobal::lineBuffers[ handle ], 0, GfxDeviceGlobal::lineBuffers[ handle ].GetFaceCount(), shader, BlendMode::Off, DepthFunc::LessOrEqualWriteOn, CullMode::Off, FillMode::Solid, GfxDevice::PrimitiveTopology::Lines );
}

void ae3d::GfxDevice::Draw( VertexBuffer& vertexBuffer, int startIndex, int endIndex, Shader& shader, BlendMode blendMode, DepthFunc depthFunc, CullMode cullMode, FillMode fillMode, PrimitiveTopology topology )
{
    Statistics::IncDrawCalls();

    for (int slot = 0; slot < 4; ++slot)
    {
        if (!textures[ slot ])
        {
            textures[ slot ] = Texture2D::GetDefaultTexture()->GetMetalTexture();
        }
    }

    if (!textures[ 4 ])
    {
        textures[ 4 ] = TextureCube::GetDefaultTexture()->GetMetalTexture();
    }
    
    DataType pixelFormat = GfxDeviceGlobal::currentRenderTargetDataType;

    const int sampleCount = GfxDeviceGlobal::isRenderingToTexture ? 1 : GfxDeviceGlobal::sampleCount;
    MTLPixelFormat depthFormat = MTLPixelFormatDepth32Float;

    depthFormat = MTLPixelFormatDepth32Float;

    id <MTLRenderPipelineState> pso = GetPSO( shader, blendMode, vertexBuffer.GetVertexFormat(), pixelFormat,
                                             depthFormat, sampleCount, topology );
    if (GfxDeviceGlobal::cachedPSO != pso)
    {
        GfxDeviceGlobal::cachedPSO = pso;
        [renderEncoder setRenderPipelineState:GfxDeviceGlobal::cachedPSO];
    }
    
    [renderEncoder setVertexBuffer:vertexBuffer.GetVertexBuffer() offset:0 atIndex:0];
    [renderEncoder setVertexBuffer:GetCurrentUniformBuffer() offset:0 atIndex:5];
    
    MTLViewport viewport;
    viewport.originX = GfxDeviceGlobal::viewport[ 0 ];
    viewport.originY = GfxDeviceGlobal::viewport[ 1 ];
    viewport.width = GfxDeviceGlobal::viewport[ 2 ];
    viewport.height = GfxDeviceGlobal::viewport[ 3 ];
    viewport.znear = 0;
    viewport.zfar = 1;
    [renderEncoder setViewport:viewport];
    
    const bool isStandard = shader.GetMetalVertexShaderName() == "standard_vertex";
    
    if (isStandard)
    {
        id< MTLBuffer > buffers[] = { GetCurrentUniformBuffer(), GfxDeviceGlobal::lightTiler.GetPerTileLightIndexBuffer(),
            GfxDeviceGlobal::lightTiler.GetPointLightCenterAndRadiusBuffer(), GfxDeviceGlobal::lightTiler.GetSpotLightCenterAndRadiusBuffer(),
            GfxDeviceGlobal::lightTiler.GetPointLightColorBuffer(), GfxDeviceGlobal::lightTiler.GetSpotLightParamsBuffer(),
            GfxDeviceGlobal::lightTiler.GetSpotLightColorBuffer()
        };
        NSRange range = { 5, 7 };
        NSUInteger offsets[] = { 0, 0, 0, 0, 0, 0, 0 };
        [renderEncoder setFragmentBuffers:buffers offsets:offsets withRange:range];
    }
    else
    {
        [renderEncoder setFragmentBuffer:GetCurrentUniformBuffer() offset:0 atIndex:5];
    }
    
    static CullMode cachedCullMode = CullMode::Off;
    if (cullMode != cachedCullMode)
    {
        cachedCullMode = cullMode;
        [renderEncoder setCullMode:(cullMode == CullMode::Back) ? MTLCullModeBack : MTLCullModeNone];
    }
    
    static FillMode cachedTriangleFillMode = FillMode::Solid;
    if (fillMode != cachedTriangleFillMode)
    {
        cachedTriangleFillMode = fillMode;
        [renderEncoder setTriangleFillMode:(fillMode == FillMode::Solid ? MTLTriangleFillMode::MTLTriangleFillModeFill : MTLTriangleFillMode::MTLTriangleFillModeLines)];
    }
    
    if (isStandard)
    {
        NSRange range = { 0, 5 };
        [renderEncoder setFragmentTextures:textures withRange:range ];
    }
    else
    {
        [renderEncoder setFragmentTexture:textures[ 0 ] atIndex:0];
        [renderEncoder setFragmentTexture:textures[ 1 ] atIndex:1];
        [renderEncoder setFragmentTexture:textures[ 4 ] atIndex:4];
    }
    
    if (depthFunc == DepthFunc::LessOrEqualWriteOff)
    {
        [renderEncoder setDepthStencilState:depthStateLessEqualWriteOff];
    }
    else if (depthFunc == DepthFunc::LessOrEqualWriteOn)
    {
        [renderEncoder setDepthStencilState:depthStateLessEqualWriteOn];
    }
    else if (depthFunc == DepthFunc::NoneWriteOff)
    {
        [renderEncoder setDepthStencilState:depthStateNoneWriteOff];
    }
    else
    {
        System::Assert( false, "unhandled depth function" );
        [renderEncoder setDepthStencilState:depthStateLessEqualWriteOn];
    }
    
    NSRange range = { 0, 5 };
    [renderEncoder setFragmentSamplerStates:GfxDeviceGlobal::samplerStates withRange:range ];
    
    if (vertexBuffer.GetVertexFormat() == VertexBuffer::VertexFormat::PTNTC)
    {
        // No need to set extra buffers as vertexBuffer contains all attributes.
        [renderEncoder setVertexBuffer:nil offset:0 atIndex:1];
    }
    else if (vertexBuffer.GetVertexFormat() == VertexBuffer::VertexFormat::PTNTC_Skinned)
    {
        // No need to set extra buffers as vertexBuffer contains all attributes.
        [renderEncoder setVertexBuffer:nil offset:0 atIndex:1];
    }
    else if (vertexBuffer.GetVertexFormat() == VertexBuffer::VertexFormat::PTN)
    {
        [renderEncoder setVertexBuffer:vertexBuffer.colorBuffer offset:0 atIndex:1];
    }
    else if (vertexBuffer.GetVertexFormat() == VertexBuffer::VertexFormat::PTC)
    {
        [renderEncoder setVertexBuffer:vertexBuffer.normalBuffer offset:0 atIndex:1];
    }
    else
    {
        System::Assert( false, "Unhandled vertex format" );
    }
    
    UploadPerObjectUbo();
    
    if (topology == PrimitiveTopology::Triangles)
    {
        [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                  indexCount:(endIndex - startIndex) * 3
                               indexType:MTLIndexTypeUInt16
                             indexBuffer:vertexBuffer.GetIndexBuffer()
                       indexBufferOffset:startIndex * 2 * 3];
    }
    else // MTLPrimitiveTypeLine
    {
        [renderEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:vertexBuffer.GetFaceCount()];
    }
    
    textures[ 12 ] = TextureCube::GetDefaultTexture()->GetMetalTexture();
    textures[ 2 ] = Texture2D::GetDefaultTexture()->GetMetalTexture();
}

void ae3d::GfxDevice::BeginLightCullerGpuQuery()
{
}

void ae3d::GfxDevice::EndLightCullerGpuQuery()
{
}

void ae3d::GfxDevice::BeginFrame()
{
    GfxDeviceGlobal::cachedPSO = nil;
    commandBuffer = [commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";
    
    for (int slot = 0; slot < 5; ++slot)
    {
        textures[ slot ] = nullptr;
    }
}

void ae3d::GfxDevice::PresentDrawable()
{
    if (view.currentDrawable != nil)
    {
        [commandBuffer presentDrawable:view.currentDrawable];
        [commandBuffer commit];
    }
    
    ++GfxDeviceGlobal::frameIndex;
}

void ae3d::GfxDevice::SetClearColor( float red, float green, float blue )
{
    clearColor[ 0 ] = red;
    clearColor[ 1 ] = green;
    clearColor[ 2 ] = blue;
}

void ae3d::GfxDevice::ReleaseGPUObjects()
{
}

void ae3d::GfxDevice::BeginBackBufferEncoding()
{
    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    
    if (renderPassDescriptor != nil)
    {
        commandBuffer = [commandQueue commandBuffer];
        commandBuffer.label = @"Backbuffer";

        renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"BackBufferRenderEncoder";
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    }
    else
    {
        renderEncoder = nil;
    }
    
    GfxDeviceGlobal::currentRenderTargetDataType = ae3d::DataType::UByte;
}

void ae3d::GfxDevice::EndBackBufferEncoding()
{
    [renderEncoder endEncoding];
}

void ae3d::GfxDevice::SetRenderTarget( ae3d::RenderTexture* renderTexture, unsigned cubeMapFace )
{
    if (GfxDeviceGlobal::isRenderingToTexture)
    {
        [renderEncoder endEncoding];
        [commandBuffer commit];
    }
    
    GfxDeviceGlobal::isRenderingToTexture = renderTexture != nullptr;

    if (!renderTexture || renderTexture->GetMetalTexture() == nil)
    {
        return;
    }

    auto texture = renderTexture->GetMetalTexture();
    auto depthTexture = renderTexture->GetMetalDepthTexture();

    MTLLoadAction texLoadAction = MTLLoadActionLoad;
    MTLLoadAction depthLoadAction = MTLLoadActionLoad;

    if (GfxDeviceGlobal::clearFlags & ae3d::GfxDevice::ClearFlags::Color)
    {
        texLoadAction = MTLLoadActionClear;
    }

    if (GfxDeviceGlobal::clearFlags & ae3d::GfxDevice::ClearFlags::Depth)
    {
        depthLoadAction = MTLLoadActionClear;
    }

    renderPassDescriptorFBO.colorAttachments[0].slice = cubeMapFace;
    renderPassDescriptorFBO.colorAttachments[0].texture = texture;
    renderPassDescriptorFBO.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPassDescriptorFBO.colorAttachments[0].clearColor = MTLClearColorMake( clearColor[0], clearColor[1], clearColor[2], clearColor[3] );
    renderPassDescriptorFBO.colorAttachments[0].loadAction = texLoadAction;
    renderPassDescriptorFBO.stencilAttachment = nil;

    renderPassDescriptorFBO.depthAttachment.slice = cubeMapFace;
    renderPassDescriptorFBO.depthAttachment.texture = depthTexture;
    renderPassDescriptorFBO.depthAttachment.loadAction = depthLoadAction;
    renderPassDescriptorFBO.depthAttachment.clearDepth = 1.0;

    commandBuffer = [commandQueue commandBuffer];
    commandBuffer.label = @"RenderTarget";

    renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptorFBO];
    renderEncoder.label = [NSString stringWithUTF8String:renderTexture->GetName()];
    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];

    GfxDeviceGlobal::currentRenderTargetDataType = renderTexture->GetDataType();
    GfxDeviceGlobal::cachedPSO = nil;
}

