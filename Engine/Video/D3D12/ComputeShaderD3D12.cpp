#include "ComputeShader.hpp"
#include <d3d12.h>
#include <d3dcompiler.h>
#include "FileSystem.hpp"
#include "System.hpp"
#include "Macros.hpp"

namespace GfxDeviceGlobal
{
    extern ID3D12Device* device;
    extern ID3D12GraphicsCommandList* graphicsCommandList;
    extern ID3D12RootSignature* rootSignatureTileCuller;
    extern ID3D12PipelineState* lightTilerPSO;
}

namespace Global
{
    std::vector< ID3DBlob* > computeShaders;
}

void DestroyComputeShaders()
{
    for (std::size_t i = 0; i < Global::computeShaders.size(); ++i)
    {
        AE3D_SAFE_RELEASE( Global::computeShaders[ i ] );
    }
}

void ae3d::ComputeShader::Dispatch( unsigned groupCountX, unsigned groupCountY, unsigned groupCountZ )
{
    System::Assert( GfxDeviceGlobal::graphicsCommandList != nullptr, "graphics command list not initialized" );

    D3D12_DESCRIPTOR_HEAP_DESC desc = {};
    desc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
    desc.NumDescriptors = 350;
    desc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
    desc.NodeMask = 1;

    ID3D12DescriptorHeap* tempHeap = nullptr;
    HRESULT hr = GfxDeviceGlobal::device->CreateDescriptorHeap( &desc, IID_PPV_ARGS( &tempHeap ) );
    AE3D_CHECK_D3D( hr, "Failed to create CBV_SRV_UAV descriptor heap" );
    //GfxDeviceGlobal::frameHeaps.push_back( tempHeap );
    tempHeap->SetName( L"LightTiler heap" );

    D3D12_CPU_DESCRIPTOR_HANDLE handle = tempHeap->GetCPUDescriptorHandleForHeapStart();

    D3D12_CONSTANT_BUFFER_VIEW_DESC cbvDesc = {};
    cbvDesc.BufferLocation = uniformBuffers[ 0 ]->GetGPUVirtualAddress();
    cbvDesc.SizeInBytes = D3D12_CONSTANT_BUFFER_DATA_PLACEMENT_ALIGNMENT * 2;
    GfxDeviceGlobal::device->CreateConstantBufferView( &cbvDesc, handle );

    handle.ptr += GfxDeviceGlobal::device->GetDescriptorHandleIncrementSize( D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV );

    D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
    srvDesc.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
    srvDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
    srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
    srvDesc.Texture2D.MipLevels = 1;
    srvDesc.Texture2D.MostDetailedMip = 0;
    srvDesc.Texture2D.PlaneSlice = 0;
    srvDesc.Texture2D.ResourceMinLODClamp = 0.0f;

    GfxDeviceGlobal::device->CreateShaderResourceView( textureBuffers[ 1 ], &srvDesc, handle );

    GfxDeviceGlobal::graphicsCommandList->SetPipelineState( GfxDeviceGlobal::lightTilerPSO );
    GfxDeviceGlobal::graphicsCommandList->SetComputeRootSignature( GfxDeviceGlobal::rootSignatureTileCuller );
    //GfxDeviceGlobal::graphicsCommandList->SetComputeRootDescriptorTable( 0, tempHeap->GetGPUDescriptorHandleForHeapStart() );
    //GfxDeviceGlobal::graphicsCommandList->SetDescriptorHeaps( 2, &descHeaps[ 0 ] );
    GfxDeviceGlobal::graphicsCommandList->Dispatch( groupCountX, groupCountY, groupCountZ );
}

void ae3d::ComputeShader::Load( const char* source )
{
    uniformBuffers[ 0 ] = uniformBuffers[ 1 ] = uniformBuffers[ 2 ] = nullptr;
    textureBuffers[ 0 ] = textureBuffers[ 1 ] = textureBuffers[ 2 ] = nullptr;
    uavBuffers[ 0 ] = uavBuffers[ 1 ] = uavBuffers[ 2 ] = nullptr;

    const std::size_t sourceLength = std::string( source ).size();
    ID3DBlob* blobError = nullptr;
    HRESULT hr = D3DCompile( source, sourceLength, "CSMain", nullptr /*defines*/, nullptr, "CSMain", "cs_5_0",
                             D3DCOMPILE_ENABLE_STRICTNESS | D3DCOMPILE_WARNINGS_ARE_ERRORS, 0, &blobShader, &blobError );
    if (FAILED( hr ))
    {
        ae3d::System::Print( "Unable to compile compute shader: %s!\n", blobError->GetBufferPointer() );
        blobError->Release();
        return;
    }

    Global::computeShaders.push_back( blobShader );
}

void ae3d::ComputeShader::Load( const char* /*metalShaderName*/, const FileSystem::FileContentsData& dataHLSL, const FileSystem::FileContentsData& /*dataSPIRV*/ )
{
    const std::string dataStr = std::string( std::begin( dataHLSL.data ), std::end( dataHLSL.data ) );
    Load( dataStr.c_str() );
}

void ae3d::ComputeShader::SetRenderTexture( RenderTexture* renderTexture, unsigned slot )
{

}

void ae3d::ComputeShader::SetUniformBuffer( unsigned slot, ID3D12Resource* buffer )
{
    if (slot < 3)
    {
        uniformBuffers[ slot ] = buffer;
    }
    else
    {
        System::Print( "SetUniformBuffer: too high slot, max is 3\n" );
    }
}

void ae3d::ComputeShader::SetTextureBuffer( unsigned slot, ID3D12Resource* buffer )
{
    if (slot < 3)
    {
        textureBuffers[ slot ] = buffer;
    }
    else
    {
        System::Print( "SetTextureBuffer: too high slot, max is 3\n" );
    }
}

void ae3d::ComputeShader::SetUAVBuffer( unsigned slot, ID3D12Resource* buffer )
{
    if (slot < 3)
    {
        uavBuffers[ slot ] = buffer;
    }
    else
    {
        System::Print( "SetUAVBuffer: too high slot, max is 3\n" );
    }
}
