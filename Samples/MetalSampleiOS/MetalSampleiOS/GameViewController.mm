#include <vector>
#include <map>
#import "GameViewController.h"
#import <CoreMotion/CoreMotion.h>

#import "Aether3D_iOS/Array.hpp"
#import "Aether3D_iOS/AudioClip.hpp"
#import "Aether3D_iOS/AudioSourceComponent.hpp"
#import "Aether3D_iOS/ComputeShader.hpp"
#import "Aether3D_iOS/CameraComponent.hpp"
#import "Aether3D_iOS/DirectionalLightComponent.hpp"
#import "Aether3D_iOS/GameObject.hpp"
#import "Aether3D_iOS/FileSystem.hpp"
#import "Aether3D_iOS/Font.hpp"
#import "Aether3D_iOS/Material.hpp"
#import "Aether3D_iOS/Mesh.hpp"
#import "Aether3D_iOS/MeshRendererComponent.hpp"
#import "Aether3D_iOS/PointLightComponent.hpp"
#import "Aether3D_iOS/SpotLightComponent.hpp"
#import "Aether3D_iOS/Scene.hpp"
#import "Aether3D_iOS/Shader.hpp"
#import "Aether3D_iOS/System.hpp"
#import "Aether3D_iOS/Texture2D.hpp"
#import "Aether3D_iOS/TextureCube.hpp"
#import "Aether3D_iOS/TransformComponent.hpp"
#import "Aether3D_iOS/TextRendererComponent.hpp"
#import "Aether3D_iOS/Vec3.hpp"

const int POINT_LIGHT_COUNT = (50 * 40 + 48);
#define MULTISAMPLE_COUNT 1
#define MAX_UI_VERTEX_MEMORY (512 * 1024)
#define MAX_UI_ELEMENT_MEMORY (128 * 1024)
const bool TestBloom = true;
const bool TestSSAO = false;

// *Really* minimal PCG32 code / (c) 2014 M.E. O'Neill / pcg-random.org
// Licensed under Apache License 2.0 (NO WARRANTY, etc. see website)
struct pcg32_random_t
{
    std::uint64_t state;
    std::uint64_t inc;
};

std::uint32_t pcg32_random_r( pcg32_random_t* rng )
{
    std::uint64_t oldstate = rng->state;
    rng->state = oldstate * 6364136223846793005ULL + (rng->inc|1);
    std::uint32_t xorshifted = (std::uint32_t)( ((oldstate >> 18u) ^ oldstate) >> 27u );
    std::int32_t rot = oldstate >> 59u;
    return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
}

pcg32_random_t rng;

int Random100()
{
    return pcg32_random_r( &rng );
}

struct MyTouch
{
    UITouch* uiTouch;
    int x, y;
};

MyTouch gTouches[ 8 ];
int gTouchCount = 0;

@implementation GameViewController
{
    MTKView* _view;
    id <MTLDevice> device;
    
    ae3d::GameObject camera2d;
    ae3d::GameObject camera3d;
    ae3d::GameObject rtCamera;
    ae3d::GameObject cube;
    ae3d::GameObject cubeFloor;
    ae3d::GameObject standardCube;
    ae3d::GameObject text;
    ae3d::GameObject dirLight;
    ae3d::GameObject pointLight;
    ae3d::GameObject spotLight;
    ae3d::GameObject bigCube;
    ae3d::GameObject bigCube2;
    ae3d::GameObject pointLights[ POINT_LIGHT_COUNT ];
    ae3d::GameObject audioContainer;
    ae3d::AudioClip audioClip;
    ae3d::Scene scene;
    ae3d::Font font;
    ae3d::Mesh cubeMesh;
    ae3d::Material cubeMaterial;
    ae3d::Material standardMaterial;
    ae3d::Shader shader;
    ae3d::Shader standardShader;
    ae3d::ComputeShader downSampleAndThresholdShader;
    ae3d::ComputeShader blurShader;
    ae3d::ComputeShader ssaoShader;
    ae3d::ComputeShader composeShader;
    ae3d::Texture2D fontTex;
    ae3d::Texture2D gliderTex;
    ae3d::Texture2D astcTex;
    ae3d::Texture2D noiseTex;
    ae3d::Texture2D ssaoTex;
    ae3d::Texture2D bloomTex;
    ae3d::Texture2D blurTex;
    ae3d::Texture2D blurTex2;
    ae3d::Texture2D ssaoBlurTex;
    ae3d::RenderTexture cameraTex;
    ae3d::RenderTexture camera2dTex;
    ae3d::TextureCube skyTex;
    
    std::vector< ae3d::GameObject > sponzaGameObjects;
    std::map< std::string, ae3d::Material* > sponzaMaterialNameToMaterial;
    std::map< std::string, ae3d::Texture2D* > sponzaTextureNameToTexture;
    Array< ae3d::Mesh* > sponzaMeshes;
    int touchBeginX;
    int touchBeginY;
    CMMotionManager* motionManager;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    motionManager = [[CMMotionManager alloc] init];

    if (motionManager.deviceMotionAvailable)
    {
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0;
        [motionManager startDeviceMotionUpdates];
        NSLog(@"Device Motion Manager Started");
    }
    
    touchBeginX = 0;
    touchBeginY = 0;
    
    device = MTLCreateSystemDefaultDevice();
    assert( device );
    
    [self _setupView];
    [self _reshape];

    ae3d::System::InitMetal( device, _view, MULTISAMPLE_COUNT, MAX_UI_VERTEX_MEMORY, MAX_UI_ELEMENT_MEMORY );
    ae3d::System::LoadBuiltinAssets();
    ae3d::System::InitAudio();
    
    audioClip.Load( ae3d::FileSystem::FileContents( "sine340.wav" ) );
    
    audioContainer.AddComponent<ae3d::AudioSourceComponent>();
    audioContainer.GetComponent<ae3d::AudioSourceComponent>()->SetClipId( audioClip.GetId() );
    audioContainer.GetComponent<ae3d::AudioSourceComponent>()->Play();

    cameraTex.Create2D( self.view.bounds.size.width * 2, self.view.bounds.size.height * 2, ae3d::DataType::Float16, ae3d::TextureWrap::Clamp, ae3d::TextureFilter::Linear, "cameraTex", MULTISAMPLE_COUNT > 1, ae3d::RenderTexture::UavFlag::Disabled );
    camera2dTex.Create2D( self.view.bounds.size.width * 2, self.view.bounds.size.height * 2, ae3d::DataType::Float16, ae3d::TextureWrap::Clamp, ae3d::TextureFilter::Linear, "camera2dTex", false, ae3d::RenderTexture::UavFlag::Disabled );
    blurTex.CreateUAV( self.view.bounds.size.width, self.view.bounds.size.height, "blurTex", ae3d::DataType::Float, nullptr );
    blurTex2.CreateUAV( self.view.bounds.size.width, self.view.bounds.size.height, "blurTex2", ae3d::DataType::Float, nullptr );
    bloomTex.CreateUAV( self.view.bounds.size.width, self.view.bounds.size.height, "bloomTex", ae3d::DataType::Float, nullptr );
    
    camera2d.AddComponent<ae3d::CameraComponent>();
    camera2d.GetComponent<ae3d::CameraComponent>()->SetProjection( 0, self.view.bounds.size.width, self.view.bounds.size.height, 0, 0, 1 );
    camera2d.GetComponent<ae3d::CameraComponent>()->SetProjectionType( ae3d::CameraComponent::ProjectionType::Orthographic );
    camera2d.GetComponent<ae3d::CameraComponent>()->SetClearFlag( ae3d::CameraComponent::ClearFlag::Depth );
    camera2d.GetComponent<ae3d::CameraComponent>()->SetClearColor( ae3d::Vec3( 0.5f, 0.0f, 0.0f ) );
    camera2d.GetComponent<ae3d::CameraComponent>()->SetLayerMask( 0x2 );
    camera2d.GetComponent<ae3d::CameraComponent>()->SetRenderOrder( 2 );
    camera2d.AddComponent<ae3d::TransformComponent>();
    camera2d.SetName( "camera2d" );
    //scene.Add( &camera2d );

    const float aspect = _view.bounds.size.width / (float)_view.bounds.size.height;

    camera3d.AddComponent<ae3d::CameraComponent>();
    camera3d.GetComponent<ae3d::CameraComponent>()->SetProjection( 45, aspect, 1, 200 );
    camera3d.GetComponent<ae3d::CameraComponent>()->SetClearColor( ae3d::Vec3( 1.0f, 0.5f, 0.5f ) );
    camera3d.GetComponent<ae3d::CameraComponent>()->SetClearFlag( ae3d::CameraComponent::ClearFlag::DepthAndColor );
    camera3d.GetComponent<ae3d::CameraComponent>()->SetProjectionType( ae3d::CameraComponent::ProjectionType::Perspective );
    camera3d.GetComponent<ae3d::CameraComponent>()->SetRenderOrder( 1 );
    camera3d.GetComponent<ae3d::CameraComponent>()->SetTargetTexture( &cameraTex );
    camera3d.GetComponent<ae3d::CameraComponent>()->GetDepthNormalsTexture().Create2D( self.view.bounds.size.width * 2, self.view.bounds.size.height * 2, ae3d::DataType::Float, ae3d::TextureWrap::Clamp, ae3d::TextureFilter::Nearest, "depthNormals", false, ae3d::RenderTexture::UavFlag::Disabled );
    camera3d.AddComponent<ae3d::TransformComponent>();
    camera3d.SetName( "camera3d" );
    camera3d.GetComponent< ae3d::TransformComponent >()->LookAt( { 3, -5, -85 }, { 120, -5, -85 }, { 0, 1, 0 } );
    scene.Add( &camera3d );
    
    fontTex.Load( ae3d::FileSystem::FileContents( "textures/font.png" ), ae3d::TextureWrap::Repeat, ae3d::TextureFilter::Nearest, ae3d::Mipmaps::None, ae3d::ColorSpace::Linear, ae3d::Anisotropy::k1 );
    gliderTex.Load( ae3d::FileSystem::FileContents( "textures/glider.png" ), ae3d::TextureWrap::Repeat, ae3d::TextureFilter::Nearest, ae3d::Mipmaps::None, ae3d::ColorSpace::Linear, ae3d::Anisotropy::k1 );
    //astcTex.Load( ae3d::FileSystem::FileContents( "granite.astc" ), ae3d::TextureWrap::Repeat, ae3d::TextureFilter::Nearest, ae3d::Mipmaps::None, ae3d::ColorSpace::SRGB, ae3d::Anisotropy::k1 );

    skyTex.Load( ae3d::FileSystem::FileContents( "textures/glider.png" ), ae3d::FileSystem::FileContents( "textures/glider.png" ),
                ae3d::FileSystem::FileContents( "textures/glider.png" ), ae3d::FileSystem::FileContents( "textures/glider.png" ),
                ae3d::FileSystem::FileContents( "textures/glider.png" ), ae3d::FileSystem::FileContents( "textures/glider.png" ),
                ae3d::TextureWrap::Clamp, ae3d::TextureFilter::Linear, ae3d::Mipmaps::Generate, ae3d::ColorSpace::SRGB );

    font.LoadBMFont( &fontTex, ae3d::FileSystem::FileContents( "font_txt.fnt" ) );
    text.AddComponent<ae3d::TextRendererComponent>();
    text.GetComponent<ae3d::TextRendererComponent>()->SetText( "Aether3D Game Engine" );
    text.GetComponent<ae3d::TextRendererComponent>()->SetFont( &font );
    text.GetComponent<ae3d::TextRendererComponent>()->SetColor( ae3d::Vec4( 1, 0, 0, 1 ) );
    text.AddComponent<ae3d::TransformComponent>();
    text.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( 5, 5, 0 ) );
    text.SetLayer( 2 );
    text.SetName( "text" );
    scene.Add( &text );
    
    shader.Load( "unlit_vertex", "unlit_fragment",
                ae3d::FileSystem::FileContents(""), ae3d::FileSystem::FileContents( "" ),
                ae3d::FileSystem::FileContents(""), ae3d::FileSystem::FileContents( "" ));
    
    standardShader.Load( "standard_vertex", "standard_fragment",
                        ae3d::FileSystem::FileContents( "" ), ae3d::FileSystem::FileContents( "" ),
                        ae3d::FileSystem::FileContents( "" ), ae3d::FileSystem::FileContents( "" ));

    downSampleAndThresholdShader.Load( "downsampleAndThreshold", ae3d::FileSystem::FileContents( "" ), ae3d::FileSystem::FileContents( "" ) );
    blurShader.Load( "blur", ae3d::FileSystem::FileContents( "" ), ae3d::FileSystem::FileContents( "" ) );
    ssaoShader.Load( "ssao", ae3d::FileSystem::FileContents( "" ), ae3d::FileSystem::FileContents( "" ) );
    composeShader.Load( "compose", ae3d::FileSystem::FileContents( "" ), ae3d::FileSystem::FileContents( "" ) );

    standardMaterial.SetShader( &standardShader );
    standardMaterial.SetTexture( &gliderTex, 0 );
    //standardMaterial.SetTexture( &astcTex, 0 );
    
    cubeMaterial.SetShader( &shader );
    cubeMaterial.SetTexture( &gliderTex, 0 );
    
    cubeMesh.Load( ae3d::FileSystem::FileContents( "textured_cube.ae3d" ) );
    
    cube.AddComponent<ae3d::MeshRendererComponent>();
    cube.GetComponent<ae3d::MeshRendererComponent>()->SetMesh( &cubeMesh );
    cube.GetComponent<ae3d::MeshRendererComponent>()->SetMaterial( &cubeMaterial, 0 );
    cube.AddComponent<ae3d::TransformComponent>();
    cube.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( 0, 0, -10 ) );
    cube.SetName( "cube" );
    scene.Add( &cube );

    standardCube.AddComponent<ae3d::MeshRendererComponent>();
    standardCube.GetComponent<ae3d::MeshRendererComponent>()->SetMesh( &cubeMesh );
    standardCube.GetComponent<ae3d::MeshRendererComponent>()->SetMaterial( &standardMaterial, 0 );
    standardCube.AddComponent<ae3d::TransformComponent>();
    standardCube.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( 3, 0, -85 ) );
    scene.Add( &standardCube );
    
    cubeFloor.AddComponent<ae3d::MeshRendererComponent>();
    cubeFloor.GetComponent<ae3d::MeshRendererComponent>()->SetMesh( &cubeMesh );
    cubeFloor.GetComponent<ae3d::MeshRendererComponent>()->SetMaterial( &cubeMaterial, 0 );
    cubeFloor.AddComponent<ae3d::TransformComponent>();
    cubeFloor.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( 0, -7, -10 ) );
    cubeFloor.GetComponent<ae3d::TransformComponent>()->SetLocalScale( 4 );
    cubeFloor.SetName( "cubeFloor" );
    scene.Add( &cubeFloor );

    bigCube.AddComponent<ae3d::MeshRendererComponent>();
    bigCube.GetComponent<ae3d::MeshRendererComponent>()->SetMesh( &cubeMesh );
    bigCube.GetComponent<ae3d::MeshRendererComponent>()->SetMaterial( &cubeMaterial, 0 );
    bigCube.AddComponent<ae3d::TransformComponent>();
    bigCube.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( 0, -8, -10 ) );
    bigCube.GetComponent<ae3d::TransformComponent>()->SetLocalScale( 5 );
    //scene.Add( &bigCube );
    
    bigCube2.AddComponent<ae3d::MeshRendererComponent>();
    bigCube2.GetComponent<ae3d::MeshRendererComponent>()->SetMesh( &cubeMesh );
    bigCube2.GetComponent<ae3d::MeshRendererComponent>()->SetMaterial( &cubeMaterial, 0 );
    bigCube2.AddComponent<ae3d::TransformComponent>();
    //bigCube2.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( 0, 2, -20 ) );
    bigCube2.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( -10, -8, -10 ) );
    bigCube2.GetComponent<ae3d::TransformComponent>()->SetLocalScale( 5 );
    scene.Add( &bigCube2 );

    dirLight.AddComponent<ae3d::DirectionalLightComponent>();
    dirLight.GetComponent<ae3d::DirectionalLightComponent>()->SetCastShadow( false, 1024 );
    dirLight.AddComponent<ae3d::TransformComponent>();
    dirLight.GetComponent<ae3d::TransformComponent>()->LookAt( { 0, 0, 0 }, ae3d::Vec3( 0, -1, 0 ).Normalized(), { 0, 1, 0 } );
    dirLight.SetName( "dirLight" );
    //scene.Add( &dirLight );

    pointLight.AddComponent<ae3d::PointLightComponent>();
    pointLight.GetComponent<ae3d::PointLightComponent>()->SetCastShadow( false, 1024 );
    pointLight.GetComponent<ae3d::PointLightComponent>()->SetRadius( 1.2f );
    pointLight.AddComponent<ae3d::TransformComponent>();
    pointLight.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( 0, -3, -10 ) );
    pointLight.SetName( "pointLight" );
    //scene.Add( &pointLight );

    spotLight.AddComponent<ae3d::SpotLightComponent>();
    spotLight.GetComponent<ae3d::SpotLightComponent>()->SetCastShadow( true, 1024 );
    spotLight.GetComponent<ae3d::SpotLightComponent>()->SetConeAngle( 45 );
    spotLight.AddComponent<ae3d::TransformComponent>();
    spotLight.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( 0, -3, -10 ) );
    spotLight.SetName( "spotLight" );
    //scene.Add( &spotLight );
    
    pointLight.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( -9.8f, 0, -85 ) );
    standardCube.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( -10, 0, -85 ) );
    
    // Sponza can be downloaded from http://twiren.kapsi.fi/files/aether3d_sponza.zip and extracted into aether3d_build/Samples
#if 1
    auto res = scene.Deserialize( ae3d::FileSystem::FileContents( "sponza.scene" ), sponzaGameObjects, sponzaTextureNameToTexture,
                                 sponzaMaterialNameToMaterial, sponzaMeshes );
    
    if (res != ae3d::Scene::DeserializeResult::Success)
    {
        ae3d::System::Print( "Could not parse Sponza\n" );
    }
    
    for (auto& mat : sponzaMaterialNameToMaterial)
    {
        mat.second->SetShader( &shader );
        //mat.second->SetShader( &standardShader );
        mat.second->SetTexture( &skyTex );
    }
    
    for (std::size_t i = 0; i < sponzaGameObjects.size(); ++i)
    {
        scene.Add( &sponzaGameObjects[ i ] );
    }
#endif
    
    // Inits point lights for Forward+
    {
        int pointLightIndex = 0;
        
        for (int row = 0; row < 50; ++row)
        {
            for (int col = 0; col < 40; ++col)
            {
                pointLights[ pointLightIndex ].AddComponent<ae3d::PointLightComponent>();
                pointLights[ pointLightIndex ].GetComponent<ae3d::PointLightComponent>()->SetRadius( 3 );
                pointLights[ pointLightIndex ].GetComponent<ae3d::PointLightComponent>()->SetColor( { (Random100() % 100 ) / 100.0f, (Random100() % 100) / 100.0f, (Random100() % 100) / 100.0f } );
                pointLights[ pointLightIndex ].AddComponent<ae3d::TransformComponent>();
                pointLights[ pointLightIndex ].GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( -150 + (float)row * 5, -19, -150 + (float)col * 4 ) );
                
                scene.Add( &pointLights[ pointLightIndex ] );
                ++pointLightIndex;
            }
        }
        
        const int row = -2;
        
        for (int col = 0; col < 48; ++col)
        {
            pointLights[ pointLightIndex ].AddComponent<ae3d::PointLightComponent>();
            pointLights[ pointLightIndex ].GetComponent<ae3d::PointLightComponent>()->SetRadius( 3 );
            pointLights[ pointLightIndex ].GetComponent<ae3d::PointLightComponent>()->SetColor( { (Random100() % 100 ) / 100.0f, (Random100() % 100) / 100.0f, (Random100() % 100) / 100.0f } );
            pointLights[ pointLightIndex ].AddComponent<ae3d::TransformComponent>();
            pointLights[ pointLightIndex ].GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( -150 + (float)row * 5, -19, -150 + (float)col * 4 ) );
            
            scene.Add( &pointLights[ pointLightIndex ] );
            ++pointLightIndex;
        }
    }
}

- (void)_setupView
{
    _view = (MTKView *)self.view;
    _view.device = device;
    _view.delegate = self;
    _view.multipleTouchEnabled = YES;

    // Setup the render target, choose values based on your app
    _view.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    _view.sampleCount = MULTISAMPLE_COUNT;
    _view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
}

- (void)_render
{
    [self _update];

    static int frame = 0;
    ++frame;
    if (frame == 200)
    {
        NSLog( @"breakpoint" );
    }

    ae3d::System::SetCurrentDrawableMetal( _view );
    ae3d::System::BeginFrame();
    scene.Render();
    
    if (!TestBloom && !TestSSAO)
    {
        const int width = self.view.bounds.size.width * 2;
        const int height = self.view.bounds.size.height * 2;
        ae3d::System::Draw( &cameraTex, 0, 0, width, height, width, height, ae3d::Vec4( 1, 1, 1, 1 ), ae3d::System::BlendMode::Off );
        ae3d::System::Draw( &camera2dTex, 0, 0, width, height, width, height, ae3d::Vec4( 1, 1, 1, 1 ), ae3d::System::BlendMode::Alpha );
    }
    
    if (TestBloom)
    {
        //auto beginTime = std::chrono::steady_clock::now();
        
        downSampleAndThresholdShader.SetRenderTexture( &cameraTex, 0 );
        downSampleAndThresholdShader.SetTexture2D( &blurTex, 1 );
        downSampleAndThresholdShader.Dispatch( self.view.bounds.size.width / 16, self.view.bounds.size.height / 16, 1, "downSampleAndThreshold", 16, 16 );
        
        blurShader.SetTexture2D( &blurTex, 0 );
        blurShader.SetTexture2D( &bloomTex, 1 );
        blurShader.SetUniform( ae3d::ComputeShader::UniformName::TilesZW, 1, 0 );
        blurShader.Dispatch( self.view.bounds.size.width / 16, self.view.bounds.size.height / 16, 1, "blur", 16, 16 );
        
        blurShader.SetTexture2D( &bloomTex, 0 );
        blurShader.SetTexture2D( &blurTex, 1 );
        blurShader.SetUniform( ae3d::ComputeShader::UniformName::TilesZW, 0, 1 );
        blurShader.Dispatch( self.view.bounds.size.width / 16, self.view.bounds.size.height / 16, 1, "blur", 16, 16 );
        
        // Second blur
        blurShader.SetTexture2D( &blurTex, 0 );
        blurShader.SetTexture2D( &blurTex2, 1 );
        blurShader.SetUniform( ae3d::ComputeShader::UniformName::TilesZW, 1, 0 );
        blurShader.Dispatch( self.view.bounds.size.width / 16, self.view.bounds.size.height / 16, 1, "blur", 16, 16 );
        
        blurShader.SetTexture2D( &blurTex2, 0 );
        blurShader.SetTexture2D( &blurTex, 1 );
        blurShader.SetUniform( ae3d::ComputeShader::UniformName::TilesZW, 0, 1 );
        blurShader.Dispatch( self.view.bounds.size.width / 16, self.view.bounds.size.height / 16, 1, "blur", 16, 16 );
        
        // Third blur
        blurShader.SetTexture2D( &blurTex, 0 );
        blurShader.SetTexture2D( &blurTex2, 1 );
        blurShader.SetUniform( ae3d::ComputeShader::UniformName::TilesZW, 1, 0 );
        blurShader.Dispatch( self.view.bounds.size.width / 16, self.view.bounds.size.height / 16, 1, "blur", 16, 16 );
        
        blurShader.SetTexture2D( &blurTex2, 0 );
        blurShader.SetTexture2D( &blurTex, 1 );
        blurShader.SetUniform( ae3d::ComputeShader::UniformName::TilesZW, 0, 1 );
        blurShader.Dispatch( self.view.bounds.size.width / 16, self.view.bounds.size.height / 16, 1, "blur", 16, 16 );
                    
        /*auto endTime = std::chrono::steady_clock::now();
        auto tDiff = std::chrono::duration<double, std::milli>( endTime - beginTime ).count();
        float bloomMS_CPU = static_cast< float >(tDiff);
        System::Statistics::SetBloomTime( bloomMS_CPU, 0 );*/

        const int width = self.view.bounds.size.width * 2;
        const int height = self.view.bounds.size.height * 2;
        
        if (TestSSAO)
        {
            ae3d::System::Draw( &ssaoTex, 0, 0, width, height, width, height, ae3d::Vec4( 1, 1, 1, 1 ), ae3d::System::BlendMode::Off );
        }
        else
        {
            ae3d::System::Draw( &cameraTex, 0, 0, width, height, width, height, ae3d::Vec4( 1, 1, 1, 1 ), ae3d::System::BlendMode::Off );
        }

        //System::Draw( &cameraTex, 0, 0, width, height, width, height, ae3d::Vec4( 1, 1, 1, 1 ), ae3d::System::BlendMode::Off );
        ae3d::System::Draw( &blurTex, 0, 0, width, height, width, height, ae3d::Vec4( 1, 1, 1, 1 ), ae3d::System::BlendMode::Additive );
        ae3d::System::Draw( &camera2dTex, 0, 0, width, height, width, height, ae3d::Vec4( 1, 1, 1, 1 ), ae3d::System::BlendMode::Alpha );
    }

    scene.EndFrame();
    ae3d::System::EndFrame();
}

- (void)_reshape
{
}

- (void)_update
{
    CMAttitude* attitude = motionManager.deviceMotion.attitude;
    
    //ae3d::System::Print( "roll: %f, pitch: %f, yaw: %f\n", attitude.roll, attitude.pitch, attitude.yaw );
    
    static int angle = 0;
    ++angle;
    
    ae3d::Quaternion rotation;
    rotation = ae3d::Quaternion::FromEuler( ae3d::Vec3( angle, angle, angle ) );
    cube.GetComponent< ae3d::TransformComponent >()->SetLocalRotation( rotation );
    
    char statStr[ 512 ] = {};
    ae3d::System::Statistics::GetStatistics( statStr );
    //text.GetComponent<ae3d::TextRendererComponent>()->SetText( statStr );
    
//#ifdef TEST_FORWARD_PLUS
    /*static float y = -14;
    y += 0.1f;
    
    if (y > 30)
    {
        y = -14;
    }
    
    for (int pointLightIndex = 0; pointLightIndex < POINT_LIGHT_COUNT; ++pointLightIndex)
    {
        const ae3d::Vec3 oldPos = pointLights[ pointLightIndex ].GetComponent<ae3d::TransformComponent>()->GetLocalPosition();
        const float xOffset = (Random100() % 10) / 20.0f - (Random100() % 10) / 20.0f;
        const float yOffset = (Random100() % 10) / 20.0f - (Random100() % 10) / 20.0f;
        
        pointLights[ pointLightIndex ].GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( oldPos.x + xOffset, -18, oldPos.z + yOffset ) );
    }*/
    
//#endif

}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    [self _reshape];
}

// Called whenever the view needs to render
- (void)drawInMTKView:(nonnull MTKView *)view
{
    @autoreleasepool {
        [self _render];
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch* touch in touches)
    {
        const CGPoint touchLocation = [touch locationInView:touch.view];
        
        gTouches[ gTouchCount ].uiTouch = touch;
        gTouches[ gTouchCount ].x = touchLocation.x;
        gTouches[ gTouchCount ].y = touchLocation.y;
        
        touchBeginX = touchLocation.x;
        touchBeginY = touchLocation.y;
        
        ++gTouchCount;
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    // Updates input object's touch locations.
    const bool moveForwardOrBackward = gTouchCount > 1;
    
    for (UITouch* touch in touches)
    {
        // Just testing camera movement
        if (moveForwardOrBackward)
        {
            const CGPoint touchLocation = [touch locationInView:touch.view];
            
            float deltaY = touchLocation.y - touchBeginY;
            
            camera3d.GetComponent<ae3d::TransformComponent>()->MoveForward( deltaY / 40 );
        }
        else
        {
            const CGPoint touchLocation = [touch locationInView:touch.view];

            float deltaX = touchLocation.x - touchBeginX;
            float deltaY = touchLocation.y - touchBeginY;
            
            camera3d.GetComponent<ae3d::TransformComponent>()->OffsetRotate( ae3d::Vec3( 0, 1, 0 ), -deltaX / 40 );
            camera3d.GetComponent<ae3d::TransformComponent>()->OffsetRotate( ae3d::Vec3( 1, 0, 0 ), -deltaY / 40 );
        }
        
        // Finds the correct touch and updates its location.
        for (int t = 0; t < gTouchCount; ++t)
        {
            if (gTouches[ t ].uiTouch == touch)
            {
                const CGPoint touchLocation = [touch locationInView:touch.view];
                
                gTouches[ t ].x = touchLocation.x;
                gTouches[ t ].y = touchLocation.y;
            }
        }
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch* touch in touches)
    {
        for (int t = 0; t < gTouchCount; ++t)
        {
            if (touch == gTouches[ t ].uiTouch)
            {
                for (int j = t; j < gTouchCount - 1; ++j)
                {
                    gTouches[ j ].x = gTouches[ j + 1 ].x;
                    gTouches[ j ].y = gTouches[ j + 1 ].y;
                    gTouches[ j ].uiTouch = gTouches [ j + 1 ].uiTouch;
                }
                
                --gTouchCount;
            }
        }
    }
    
    // debug
    gTouchCount = 0;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event 
{
    gTouchCount = 0;
}

@end

