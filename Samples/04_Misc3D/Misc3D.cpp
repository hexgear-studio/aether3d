#include <string>
#include <stdint.h>
#include "Array.hpp"
#include "AudioClip.hpp"
#include "AudioSourceComponent.hpp"
#include "CameraComponent.hpp"
#include "ComputeShader.hpp"
#include "DirectionalLightComponent.hpp"
#include "FileSystem.hpp"
#include "Font.hpp"
#include "GameObject.hpp"
#include "Material.hpp"
#include "Mesh.hpp"
#include "MeshRendererComponent.hpp"
#include "PointLightComponent.hpp"
#include "RenderTexture.hpp"
#include "SpriteRendererComponent.hpp"
#include "SpotLightComponent.hpp"
#include "Scene.hpp"
#include "Shader.hpp"
#include "System.hpp"
#include "TextRendererComponent.hpp"
#include "TransformComponent.hpp"
#include "Texture2D.hpp"
#include "TextureCube.hpp"
#include "Vec3.hpp"
#include "VR.hpp"
#include "Window.hpp"

// Assets for this sample (extract into aether3d_build/Samples): http://twiren.kapsi.fi/files/aether3d_sample_v0.8.5.zip

//#define TEST_RENDER_TEXTURE_2D
//#define TEST_MSAA
//#define TEST_RENDER_TEXTURE_CUBE
//#define TEST_VERTEX_LAYOUTS
//#define TEST_SHADOWS_DIR
//#define TEST_SHADOWS_SPOT
//#define TEST_SHADOWS_POINT
//#define TEST_FORWARD_PLUS
//#define TEST_BLOOM
//#define TEST_SSAO
// Sponza can be downloaded from http://twiren.kapsi.fi/files/aether3d_sponza.zip and extracted into aether3d_build/Samples
#define TEST_SPONZA

using namespace ae3d;

// *Really* minimal PCG32 code / (c) 2014 M.E. O'Neill / pcg-random.org
// Licensed under Apache License 2.0 (NO WARRANTY, etc. see website)
struct pcg32_random_t
{
    uint64_t state;
    uint64_t inc;
};

uint32_t pcg32_random_r( pcg32_random_t* rng )
{
    uint64_t oldstate = rng->state;
    rng->state = oldstate * 6364136223846793005ULL + (rng->inc|1);
    uint32_t xorshifted = uint32_t( ((oldstate >> 18u) ^ oldstate) >> 27u );
    int32_t rot = oldstate >> 59u;
    return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
}

pcg32_random_t rng;

int Random100()
{
    return pcg32_random_r( &rng );
}

Scene scene;
GameObject camera;

void sceneRenderFunc( int eye )
{
    VR::CalcCameraForEye( camera, 0, eye );
    scene.Render();
}

int main()
{
    bool fullScreen = false;

    int originalWidth = 1920 / 1;
    int originalHeight = 1080 / 1;
    int width = originalWidth;
    int height = originalHeight;

    if (fullScreen)
    {
        width = 0;
        height = 0;
    }
    
    System::EnableWindowsMemleakDetection();
#ifdef TEST_MSAA
    Window::Create( width, height, fullScreen ? WindowCreateFlags::Fullscreen : WindowCreateFlags::MSAA4 );
#else
    Window::Create( width, height, fullScreen ? WindowCreateFlags::Fullscreen : WindowCreateFlags::Empty );
#endif
    Window::GetSize( width, height );
    
    if (fullScreen)
    {
        originalWidth = width;
        originalHeight = height;
    }

#ifdef RENDERER_D3D12
    int postHeight = originalHeight;
#else
    int postHeight = height;
#endif

    Window::SetTitle( "Misc3D" );
    VR::Init();
    System::LoadBuiltinAssets();
    System::InitAudio();
    System::InitGamePad();

#ifdef AE3D_OPENVR
    VR::GetIdealWindowSize( width, height );
#endif

    RenderTexture cameraTex;
    cameraTex.Create2D( width, height, RenderTexture::DataType::Float, TextureWrap::Clamp, TextureFilter::Linear, "cameraTex" );

    Texture2D bloomTex;
    bloomTex.CreateUAV( width / 2, height / 2, "bloomTex" );

	Texture2D blurTex;
	blurTex.CreateUAV( width / 2, height / 2, "blurTex" );

    Texture2D blurTex2;
    blurTex2.CreateUAV( width / 2, height / 2, "blurTex2" );

    Texture2D noiseTex;

    constexpr int noiseDim = 64;
    Vec4 noiseData[ noiseDim * noiseDim ];

    for (int i = 0; i < noiseDim * noiseDim; ++i)
    {
        Vec3 dir = Vec3( (Random100() / 100.0f) * 2 - 1, (Random100() / 100.0f) * 2 - 1, 0 ).Normalized();
        noiseData[ i ].x = dir.x;
        noiseData[ i ].y = dir.y;
        noiseData[ i ].z = 0;
        noiseData[ i ].w = 0;
    }

#if RENDERER_VULKAN    
    noiseTex.LoadFromData( noiseData, noiseDim, noiseDim, 4, "noiseData", VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_STORAGE_BIT, true );
#else
    noiseTex.LoadFromData( noiseData, noiseDim, noiseDim, 4, "noiseData" );    
#endif
    noiseTex.SetLayout( TextureLayout::ShaderRead );
    
    RenderTexture resolvedTex;
    resolvedTex.Create2D( width, height, RenderTexture::DataType::Float, TextureWrap::Clamp, TextureFilter::Linear, "resolve" );
        
    RenderTexture camera2dTex;
    camera2dTex.Create2D( width, height, RenderTexture::DataType::Float, TextureWrap::Clamp, TextureFilter::Linear, "camera2dTex" );

    camera.AddComponent<CameraComponent>();
    camera.GetComponent<CameraComponent>()->SetClearColor( Vec3( 0, 0, 0 ) );
    camera.GetComponent<CameraComponent>()->SetProjectionType( CameraComponent::ProjectionType::Perspective );
    camera.GetComponent<CameraComponent>()->SetProjection( 45, (float)originalWidth / (float)originalHeight, 0.1f, 200 );
    camera.GetComponent<CameraComponent>()->GetDepthNormalsTexture().Create2D( originalWidth, originalHeight, ae3d::RenderTexture::DataType::Float, ae3d::TextureWrap::Clamp, ae3d::TextureFilter::Nearest, "depthnormals" );
    camera.GetComponent<CameraComponent>()->SetClearFlag( CameraComponent::ClearFlag::DepthAndColor );
    camera.GetComponent<CameraComponent>()->SetRenderOrder( 1 );
#ifndef AE3D_OPENVR
    camera.GetComponent<CameraComponent>()->SetTargetTexture( &cameraTex );
#endif
    //camera.GetComponent<CameraComponent>()->SetViewport( 0, 0, originalWidth / 2, originalHeight );
    camera.AddComponent<TransformComponent>();
    camera.GetComponent<TransformComponent>()->LookAt( { 0, 0, -80 }, { 0, 0, 100 }, { 0, 1, 0 } );
    camera.SetName( "camera" );

#ifdef TEST_RENDER_TEXTURE_CUBE
    RenderTexture cubeRT;
    cubeRT.CreateCube( 512, ae3d::RenderTexture::DataType::UByte, ae3d::TextureWrap::Repeat, ae3d::TextureFilter::Linear, "cubeRT" );
    
    GameObject cameraCubeRT;
    cameraCubeRT.AddComponent<CameraComponent>();
    cameraCubeRT.GetComponent<CameraComponent>()->SetClearColor( Vec3( 0, 0, 0 ) );
    cameraCubeRT.GetComponent<CameraComponent>()->SetProjectionType( CameraComponent::ProjectionType::Perspective );
    cameraCubeRT.GetComponent<CameraComponent>()->SetProjection( 45, 1, 1, 400 );
    cameraCubeRT.GetComponent<CameraComponent>()->SetTargetTexture( &cubeRT );
    cameraCubeRT.GetComponent<CameraComponent>()->SetClearFlag( CameraComponent::ClearFlag::DepthAndColor );
    cameraCubeRT.AddComponent<TransformComponent>();
    cameraCubeRT.GetComponent<TransformComponent>()->LookAt( { 5, 0, -70 }, { 0, 0, -100 }, { 0, 1, 0 } );
    cameraCubeRT.SetName( "cameraCubeRT" );
#endif
    
    GameObject camera2d;
    camera2d.AddComponent<CameraComponent>();
    camera2d.GetComponent<CameraComponent>()->SetClearColor( Vec3( 0, 0, 0 ) );
    camera2d.GetComponent<CameraComponent>()->SetProjectionType( CameraComponent::ProjectionType::Orthographic );
    camera2d.GetComponent<CameraComponent>()->SetProjection( 0, (float)width, (float)height, 0, 0, 1 );
    camera2d.GetComponent<CameraComponent>()->SetClearFlag( CameraComponent::ClearFlag::DepthAndColor );
    camera2d.GetComponent<CameraComponent>()->SetLayerMask( 0x2 );
    camera2d.GetComponent<CameraComponent>()->SetTargetTexture( &camera2dTex );
    camera2d.GetComponent<CameraComponent>()->SetRenderOrder( 2 );
    camera2d.AddComponent<TransformComponent>();
    camera2d.SetName( "camera2d" );
    
    Texture2D fontTex;
    fontTex.Load( FileSystem::FileContents( "font.png" ), TextureWrap::Clamp, TextureFilter::Linear, Mipmaps::None, ColorSpace::SRGB, Anisotropy::k1 );

    Texture2D normalTex;
    normalTex.Load( FileSystem::FileContents( "textures/default_n.png" ), TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::Linear, Anisotropy::k1 );

    Texture2D whiteTex;
    whiteTex.Load( FileSystem::FileContents( "default_white.png" ), TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::SRGB, Anisotropy::k1 );

#ifdef TEST_SPONZA
    Texture2D pbrDiffuseTex;
    pbrDiffuseTex.Load( FileSystem::FileContents( "textures/pbr_metal_texture/metal_plate_d.png" ), TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::SRGB, Anisotropy::k1 );
    Texture2D pbrNormalTex;
    pbrNormalTex.Load( FileSystem::FileContents( "textures/pbr_metal_texture/metal_plate_n.png" ), TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::Linear, Anisotropy::k1 );
    Texture2D pbrRoughnessTex;
    pbrRoughnessTex.Load( FileSystem::FileContents( "textures/pbr_metal_texture/metal_plate_rough.png" ), TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::Linear, Anisotropy::k1 );
    Texture2D pbrNormalTex2;
    pbrNormalTex2.Load( FileSystem::FileContents( "grass_n_bc5.dds" ), TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::Linear, Anisotropy::k1 );
    Texture2D pbrSpecularTex;
    pbrSpecularTex.Load( FileSystem::FileContents( "spnza_bricks_a_spec_bc4.dds" ), TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::Linear, Anisotropy::k1 );
#endif
    
    Font font;
    font.LoadBMFont( &fontTex, FileSystem::FileContents( "font_txt.fnt" ) );

    GameObject statsContainer;
    statsContainer.AddComponent<TextRendererComponent>();
    statsContainer.GetComponent<TextRendererComponent>()->SetText( "Aether3D \nGame Engine" );
    statsContainer.GetComponent<TextRendererComponent>()->SetFont( &font );
    statsContainer.AddComponent<TransformComponent>();
    statsContainer.GetComponent<TransformComponent>()->SetLocalPosition( { 20, 40, 0 } );
    //statsContainer.GetComponent<TransformComponent>()->SetLocalScale( 0.5f );
    statsContainer.SetLayer( 2 );
    
    Mesh cubeMesh;
    cubeMesh.Load( FileSystem::FileContents( "textured_cube.ae3d" ) );

    Mesh cubeTangentMesh;
    cubeTangentMesh.Load( FileSystem::FileContents( "tangent_test.ae3d" ) );

    GameObject cube;
    cube.AddComponent< MeshRendererComponent >();
    cube.GetComponent< MeshRendererComponent >()->SetMesh( &cubeMesh );
    cube.AddComponent< TransformComponent >();
    cube.GetComponent< TransformComponent >()->SetLocalPosition( { 0, 4, -80 } );

    GameObject cubeTangent;
    cubeTangent.AddComponent< MeshRendererComponent >();
    cubeTangent.GetComponent< MeshRendererComponent >()->SetMesh( &cubeTangentMesh );
    cubeTangent.AddComponent< TransformComponent >();
    cubeTangent.GetComponent< TransformComponent >()->SetLocalPosition( { 0, 8, -80 } );

    GameObject rotatingCube;
    rotatingCube.AddComponent< MeshRendererComponent >();
    rotatingCube.GetComponent< MeshRendererComponent >()->SetMesh( &cubeMesh );
    //rotatingCube.GetComponent< MeshRendererComponent >()->EnableBoundingBoxDrawing( true );
    rotatingCube.AddComponent< TransformComponent >();
    rotatingCube.GetComponent< TransformComponent >()->SetLocalPosition( { -2, 0, -108 } );
    rotatingCube.GetComponent< TransformComponent >()->SetLocalScale( 1 );

    GameObject childCube;
    childCube.AddComponent< MeshRendererComponent >();
    childCube.GetComponent< MeshRendererComponent >()->SetMesh( &cubeMesh );
    childCube.AddComponent< TransformComponent >();
    childCube.GetComponent< TransformComponent >()->SetLocalPosition( { 3, 0, 0 } );
    childCube.GetComponent< TransformComponent >()->SetParent( rotatingCube.GetComponent< TransformComponent >() );

    Mesh cubeMesh2;
    cubeMesh2.Load( FileSystem::FileContents( "textured_cube.ae3d" ) );
    
    Mesh cubeMeshPTN; // Position-texcoord-normal
    cubeMeshPTN.Load( FileSystem::FileContents( "pnt_quads_2_meshes.ae3d" ) );

    Mesh animatedMesh;
    animatedMesh.Load( FileSystem::FileContents( "human_anim_test2.ae3d" ) );

#ifdef TEST_RENDER_TEXTURE_CUBE
    GameObject rtCube;
    rtCube.AddComponent< MeshRendererComponent >();
    rtCube.GetComponent< MeshRendererComponent >()->SetMesh( &cubeMesh2 );
    rtCube.AddComponent< TransformComponent >();
    rtCube.GetComponent< TransformComponent >()->SetLocalPosition( { 5, 0, -70 } );
#endif
    
    GameObject animatedGo;
    animatedGo.AddComponent< MeshRendererComponent >();
    animatedGo.GetComponent< MeshRendererComponent >()->SetMesh( &animatedMesh );
    animatedGo.AddComponent< TransformComponent >();
    animatedGo.GetComponent< TransformComponent >()->SetLocalPosition( { 13, -14, -80 } );
    animatedGo.GetComponent< TransformComponent >()->SetLocalScale( 0.0075f );
    animatedGo.GetComponent< TransformComponent >()->SetLocalRotation( Quaternion::FromEuler( { 180, 90, 0 } ) );
    animatedGo.SetName( "animatedGo" );

    Shader shader;
    shader.Load( "unlitVert", "unlitFrag",
                 FileSystem::FileContents( "unlit_vert.obj" ), FileSystem::FileContents( "unlit_frag.obj" ),
                 FileSystem::FileContents( "unlit_vert.spv" ), FileSystem::FileContents( "unlit_frag.spv" ) );

    Shader shaderSkin;
    shaderSkin.Load( "unlitVert", "unlitFrag",
                FileSystem::FileContents( "unlit_skin_vert.obj" ), FileSystem::FileContents( "unlit_frag.obj" ),
                FileSystem::FileContents( "unlit_skin_vert.spv" ), FileSystem::FileContents( "unlit_frag.spv" ) );

    ComputeShader blurShader;
	blurShader.Load( "blur", FileSystem::FileContents( "Blur.obj" ), FileSystem::FileContents( "Blur.spv" ) );

	ComputeShader downsampleAndThresholdShader;
	downsampleAndThresholdShader.Load( "downsampleAndThreshold", FileSystem::FileContents( "Bloom.obj" ), FileSystem::FileContents( "Bloom.spv" ) );

    ComputeShader ssaoShader;
	ssaoShader.Load( "ssao", FileSystem::FileContents( "ssao.obj" ), FileSystem::FileContents( "ssao.spv" ) );

    Texture2D ssaoTex;
    ssaoTex.CreateUAV( width, height, "ssaoTex" );
    
    Texture2D gliderTex;
    gliderTex.Load( FileSystem::FileContents( "glider.png" ), TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::SRGB, Anisotropy::k1 );

    Texture2D asphaltTex;
    asphaltTex.Load( FileSystem::FileContents( "asphalt.jpg" ), TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::SRGB, Anisotropy::k1 );

    Texture2D gliderClampTex;
    gliderClampTex.Load( FileSystem::FileContents( "font.png" ), TextureWrap::Clamp, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::SRGB, Anisotropy::k1 );

    Texture2D playerTex;
    playerTex.Load( FileSystem::FileContents( "player.png" ), TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::SRGB, Anisotropy::k1 );

    Material materialClamp;
    materialClamp.SetShader( &shader );
    materialClamp.SetTexture( &gliderClampTex, 0 );
    materialClamp.SetBackFaceCulling( true );

    Material material;
    material.SetShader( &shader );
    material.SetTexture( &gliderTex, 0 );
    material.SetBackFaceCulling( true );

    Material materialSkin;
    materialSkin.SetShader( &shaderSkin );
    materialSkin.SetTexture( &playerTex, 0 );

    cube.GetComponent< MeshRendererComponent >()->SetMaterial( &material, 0 );
    rotatingCube.GetComponent< MeshRendererComponent >()->SetMaterial( &material, 0 );

    childCube.GetComponent< MeshRendererComponent >()->SetMaterial( &material, 0 );

    GameObject copiedCube = cube;
    copiedCube.GetComponent< TransformComponent >()->SetLocalPosition( { 0, 6, -80 } );
    copiedCube.GetComponent< MeshRendererComponent >()->SetMaterial( &material, 0 );
    
    Shader shaderCubeMap;
    shaderCubeMap.Load( "unlitVert", "unlitFrag",
                        FileSystem::FileContents( "unlit_cube_vert.obj" ), FileSystem::FileContents( "unlit_cube_frag.obj" ),
                        FileSystem::FileContents( "unlit_cube_vert.spv" ), FileSystem::FileContents( "unlit_cube_frag.spv" ) );

    GameObject lightParent;
    //lightParent.AddComponent< MeshRendererComponent >();
    //lightParent.GetComponent< MeshRendererComponent >()->SetMesh( &cubeMesh );
    lightParent.AddComponent< TransformComponent >();
    lightParent.GetComponent< TransformComponent >()->SetLocalPosition( { 0, -2, -80 } );

    GameObject dirLight;
    dirLight.AddComponent<DirectionalLightComponent>();
#ifdef TEST_SHADOWS_DIR
    dirLight.GetComponent<DirectionalLightComponent>()->SetCastShadow( true, 2048 );
#else
    dirLight.GetComponent<DirectionalLightComponent>()->SetCastShadow( false, 2048 );
#endif
    dirLight.GetComponent<DirectionalLightComponent>()->SetColor( Vec3( 1, 1, 1 ) );
    dirLight.AddComponent<TransformComponent>();
    dirLight.GetComponent<TransformComponent>()->LookAt( { 1, 1, 1 }, Vec3( 0, -1, 0 ).Normalized(), { 0, 1, 0 } );

    GameObject spotLight;
    spotLight.AddComponent<SpotLightComponent>();
#ifdef TEST_SHADOWS_SPOT
    spotLight.GetComponent<SpotLightComponent>()->SetCastShadow( true, 1024 );
#else
    spotLight.GetComponent<SpotLightComponent>()->SetCastShadow( false, 1024 );
#endif
    spotLight.GetComponent<SpotLightComponent>()->SetRadius( 2 );
    spotLight.GetComponent<SpotLightComponent>()->SetConeAngle( 30 );
    spotLight.GetComponent<SpotLightComponent>()->SetColor( { 1, 0.5f, 0.5f } );
    spotLight.AddComponent<TransformComponent>();
    spotLight.GetComponent<TransformComponent>()->LookAt( { 0, 0, -95 }, { 0, 0, -195 }, { 0, 1, 0 } );
    //spotLight.GetComponent<TransformComponent>()->SetParent( lightParent.GetComponent< TransformComponent >() );

    GameObject pointLight;
    pointLight.AddComponent<PointLightComponent>();
#ifdef TEST_SHADOWS_POINT
    pointLight.GetComponent<PointLightComponent>()->SetCastShadow( true, 1024 );
#else
    pointLight.GetComponent<PointLightComponent>()->SetCastShadow( false, 1024 );
#endif
    pointLight.GetComponent<PointLightComponent>()->SetRadius( 1 );
    pointLight.AddComponent<TransformComponent>();
    pointLight.GetComponent<TransformComponent>()->SetLocalPosition( { 2, 0, -98 } );

    scene.SetAmbient( { 0.1f, 0.1f, 0.1f } );
    
    TextureCube skybox;
    skybox.Load( FileSystem::FileContents( "skybox/left.jpg" ), FileSystem::FileContents( "skybox/right.jpg" ),
                 FileSystem::FileContents( "skybox/bottom.jpg" ), FileSystem::FileContents( "skybox/top.jpg" ),
                 FileSystem::FileContents( "skybox/front.jpg" ), FileSystem::FileContents( "skybox/back.jpg" ),
                 TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::None, ColorSpace::SRGB );
    /*const char* path = "test_dxt1.dds";
    skybox.Load( FileSystem::FileContents( path ), FileSystem::FileContents( path ),
        FileSystem::FileContents( path ), FileSystem::FileContents( path ),
        FileSystem::FileContents( path ), FileSystem::FileContents( path ),
        TextureWrap::Clamp, TextureFilter::Linear, Mipmaps::Generate, ColorSpace::SRGB );*/
#ifdef TEST_RENDER_TEXTURE_CUBE
    Material materialCubeRT;
    materialCubeRT.SetShader( &shaderCubeMap );
    materialCubeRT.SetRenderTexture( &cubeRT, 4 );
    materialCubeRT.SetBackFaceCulling( true );

    rtCube.GetComponent< MeshRendererComponent >()->SetMaterial( &materialCubeRT, 0 );
#endif

#ifdef TEST_FORWARD_PLUS
    Shader standardShader;
    standardShader.Load( "standard_vertex", "standard_fragment",
        ae3d::FileSystem::FileContents( "Standard_vert.obj" ), ae3d::FileSystem::FileContents( "Standard_frag.obj" ),
        ae3d::FileSystem::FileContents( "Standard_vert.spv" ), ae3d::FileSystem::FileContents( "Standard_frag.spv" ) );

    Shader standardSkinShader;
    standardSkinShader.Load( "standard_skin_vertex", "standard_fragment",
        ae3d::FileSystem::FileContents( "Standard_skin_vert.obj" ), ae3d::FileSystem::FileContents( "Standard_frag.obj" ),
        ae3d::FileSystem::FileContents( "Standard_skin_vert.spv" ), ae3d::FileSystem::FileContents( "Standard_frag.spv" ) );

    Material standardMaterial;
    standardMaterial.SetShader( &standardShader );
    standardMaterial.SetTexture( &gliderTex, 0 );
    standardMaterial.SetTexture( &gliderTex, 1 );
    standardMaterial.SetTexture( &skybox );

    Material standardSkinMaterial;
    standardSkinMaterial.SetShader( &standardSkinShader );
    standardSkinMaterial.SetTexture( &playerTex, 0 );
    standardSkinMaterial.SetTexture( &playerTex, 1 );
    standardSkinMaterial.SetTexture( &skybox );

#ifdef TEST_SPONZA
    Material pbrMaterial;
    pbrMaterial.SetShader( &standardShader );
    pbrMaterial.SetTexture( &pbrDiffuseTex, 0 );
    pbrMaterial.SetTexture( &pbrNormalTex, 1 );
    //pbrMaterial.SetTexture( &pbrSpecularTex, 0 );
    pbrMaterial.SetTexture( &skybox );
    pbrMaterial.SetBackFaceCulling( true );
    rotatingCube.GetComponent< TransformComponent >()->SetLocalPosition( ae3d::Vec3( 0, 6, -94 ) );
    rotatingCube.GetComponent< TransformComponent >()->SetLocalScale( 2 );
    rotatingCube.GetComponent< MeshRendererComponent >()->SetMaterial( &pbrMaterial, 0 );

    Material materialTangent;
    materialTangent.SetShader( &standardShader );
    materialTangent.SetTexture( &normalTex, 1 );
    materialTangent.SetTexture( &whiteTex, 0 );
    cubeTangent.GetComponent< MeshRendererComponent >()->SetMaterial( &materialTangent, 0 );
#endif

    GameObject standardCubeTopCenter;
    standardCubeTopCenter.SetName( "standardCubeTopCenter" );
    standardCubeTopCenter.AddComponent<ae3d::MeshRendererComponent>();
    standardCubeTopCenter.GetComponent<ae3d::MeshRendererComponent>()->SetMesh( &cubeMesh );
    standardCubeTopCenter.GetComponent<ae3d::MeshRendererComponent>()->SetMaterial( &standardMaterial, 0 );
    standardCubeTopCenter.AddComponent<ae3d::TransformComponent>();
    standardCubeTopCenter.GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( 2, 5, -120 ) );
    standardCubeTopCenter.GetComponent<ae3d::TransformComponent>()->SetLocalScale( 2 );
    scene.Add( &standardCubeTopCenter );

    const int POINT_LIGHT_COUNT = 50 * 40;
    
    GameObject pointLights[ POINT_LIGHT_COUNT ];
    
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
                pointLights[ pointLightIndex ].GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( -150 + (float)row * 5, -12, -150 + (float)col * 4 ) );

                scene.Add( &pointLights[ pointLightIndex ] );
                ++pointLightIndex;
            }
        }
    }
#endif

#ifdef TEST_FORWARD_PLUS
    animatedGo.GetComponent< MeshRendererComponent >()->SetMaterial( &standardSkinMaterial, 0 );
#else
    animatedGo.GetComponent< MeshRendererComponent >()->SetMaterial( &materialSkin, 0 );
#endif

    std::vector< GameObject > sponzaGameObjects;
    std::map< std::string, Material* > sponzaMaterialNameToMaterial;
    std::map< std::string, Texture2D* > sponzaTextureNameToTexture;
    Array< Mesh* > sponzaMeshes;
#ifdef TEST_SPONZA
    auto res = scene.Deserialize( FileSystem::FileContents( "sponza.scene" ), sponzaGameObjects, sponzaTextureNameToTexture,
                                  sponzaMaterialNameToMaterial, sponzaMeshes );
    if (res != Scene::DeserializeResult::Success)
    {
        System::Print( "Could not parse Sponza\n" );
    }

    for (auto& mat : sponzaMaterialNameToMaterial)
    {
#ifdef TEST_FORWARD_PLUS
        mat.second->SetShader( &standardShader );
        mat.second->SetTexture( &skybox );
#else
        mat.second->SetShader( &shader );
#endif
    }
    
    for (std::size_t i = 0; i < sponzaGameObjects.size(); ++i)
    {
        scene.Add( &sponzaGameObjects[ i ] );
    }
#endif
    // Sponza ends
    
    RenderTexture rtTex;
    const auto dataType = camera2d.GetComponent<CameraComponent>()->GetTargetTexture() != nullptr ? RenderTexture::DataType::Float : RenderTexture::DataType::UByte;
    rtTex.Create2D( 512, 512, dataType, TextureWrap::Clamp, TextureFilter::Linear, "rtTex" );
    
    GameObject renderTextureContainer;
    renderTextureContainer.SetName( "renderTextureContainer" );
    renderTextureContainer.AddComponent<SpriteRendererComponent>();
#ifdef TEST_RENDER_TEXTURE_2D
    renderTextureContainer.GetComponent<SpriteRendererComponent>()->SetTexture( &rtTex, Vec3( 150, 250, -0.6f ), Vec3( 512, 512, 1 ), Vec4( 1, 1, 1, 1 ) );
#endif
    //renderTextureContainer.GetComponent<SpriteRendererComponent>()->SetTexture( &camera.GetComponent< CameraComponent >()->GetDepthNormalsTexture(), Vec3( 150, 250, -0.6f ), Vec3( 256, 256, 1 ), Vec4( 1, 1, 1, 1 ) );
    renderTextureContainer.SetLayer( 2 );

    GameObject rtCamera;
    rtCamera.SetName( "RT camera" );
    rtCamera.AddComponent<CameraComponent>();
    //rtCamera.GetComponent<CameraComponent>()->SetProjection( 0, (float)rtTex.GetWidth(), 0,(float)rtTex.GetHeight(), 0, 1 );
    rtCamera.GetComponent<CameraComponent>()->SetProjection( 45, (float)width / (float)height, 1, 200 );
    rtCamera.GetComponent<CameraComponent>()->SetProjectionType( CameraComponent::ProjectionType::Perspective );
    rtCamera.GetComponent<CameraComponent>()->SetClearColor( Vec3( 0, 0, 0 ) );
    rtCamera.GetComponent<CameraComponent>()->SetTargetTexture( &rtTex );
    rtCamera.GetComponent<CameraComponent>()->SetLayerMask( 0x1 );
    rtCamera.GetComponent<CameraComponent>()->SetRenderOrder( 0 );
    rtCamera.AddComponent<TransformComponent>();
    //rtCamera.GetComponent<TransformComponent>()->SetLocalPosition( Vec3( 0, 0, -70 ) );
    
    GameObject rtCameraParent;
    rtCameraParent.AddComponent<TransformComponent>();
    rtCameraParent.GetComponent<TransformComponent>()->SetLocalPosition( Vec3( 0, 0, -70 ) );
    rtCamera.GetComponent<TransformComponent>()->SetParent( rtCameraParent.GetComponent<TransformComponent>() );
    
    Texture2D transTex;
    transTex.Load( FileSystem::FileContents( "trans50.png" ), TextureWrap::Repeat, TextureFilter::Linear, Mipmaps::None, ColorSpace::SRGB, Anisotropy::k1 );

    Material transMaterial;
    transMaterial.SetShader( &shader );
    transMaterial.SetTexture( &transTex, 0 );
    transMaterial.SetBackFaceCulling( true );
    transMaterial.SetBlendingMode( Material::BlendingMode::Alpha );
    
    GameObject transCube1;
    transCube1.SetName( "transCube1" );
    transCube1.AddComponent< MeshRendererComponent >();
    transCube1.GetComponent< MeshRendererComponent >()->SetMesh( &cubeMesh );
    transCube1.GetComponent< MeshRendererComponent >()->SetMaterial( &transMaterial, 0 );
    transCube1.AddComponent< TransformComponent >();
    transCube1.GetComponent< TransformComponent >()->SetLocalPosition( { 2, 0, -70 } );
    
    scene.SetSkybox( &skybox );
    scene.Add( &camera );
#if !defined( AE3D_OPENVR ) && !defined( TEST_MSAA )
    scene.Add( &camera2d );
    scene.Add( &statsContainer );
#endif
#ifdef TEST_RENDER_TEXTURE_CUBE
    scene.Add( &rtCube );
    scene.Add( &cameraCubeRT );
#endif
    scene.Add( &lightParent );
    scene.Add( &animatedGo );
    scene.Add( &cubeTangent );
    scene.Add( &childCube );
    //scene.Add( &copiedCube );
    scene.Add( &rotatingCube );
    scene.Add( &cube );

#ifdef TEST_SHADOWS_POINT
    scene.Add( &pointLight );
#endif
    //#ifdef TEST_SHADOWS_DIR
    scene.Add( &dirLight );
    //#endif
    scene.Add( &spotLight );
#ifdef TEST_RENDER_TEXTURE_2D
    scene.Add( &renderTextureContainer );
    scene.Add( &rtCamera );
#endif
    scene.Add( &transCube1 );
    
    AudioClip audioClip;
    audioClip.Load( FileSystem::FileContents( "sine340.wav" ) );
    
    cube.AddComponent<AudioSourceComponent>();
    cube.GetComponent<AudioSourceComponent>()->SetClipId( audioClip.GetId() );
    cube.GetComponent<AudioSourceComponent>()->Set3D( true );
    //cube.GetComponent<AudioSourceComponent>()->Play();

    bool quit = false;
    
    int lastMouseX = 0;
    int lastMouseY = 0;
    
    float yaw = 0;
    float gamePadLeftThumbX = 0;
    float gamePadLeftThumbY = 0;
    float gamePadRightThumbX = 0;
    float gamePadRightThumbY = 0;
    
    float angle = 0;
    Vec3 moveDir;

    bool reload = false;
    bool ssao = true;
    
    while (Window::IsOpen() && !quit)
    {
        Window::PumpEvents();
        WindowEvent event;
        
        ++angle;
        Quaternion rotation;
        Vec3 axis( 0, 1, 0 );
        rotation.FromAxisAngle( axis, angle );
        cube.GetComponent< TransformComponent >()->SetLocalRotation( rotation );

        lightParent.GetComponent< TransformComponent >()->SetLocalRotation( rotation );
        //spotLight.GetComponent< TransformComponent >()->SetLocalRotation( rotation );

        axis = Vec3( 1, 1, 1 ).Normalized();
        rotation.FromAxisAngle( axis, angle );
        rotatingCube.GetComponent< TransformComponent >()->SetLocalRotation( rotation );

        //cubeTangent.GetComponent< TransformComponent >()->SetLocalRotation( rotation );

        axis = Vec3( 0, 1, 0 ).Normalized();
        rotation.FromAxisAngle( axis, angle );
        rtCamera.GetComponent<TransformComponent>()->SetLocalRotation( rotation );

        while (Window::PollEvent( event ))
        {
            if (event.type == WindowEventType::Close)
            {
                quit = true;
            }
            else if (event.type == WindowEventType::KeyDown)
            {
                KeyCode keyCode = event.keyCode;
                
                const float velocity = 0.3f;
                
                if (keyCode == KeyCode::Escape)
                {
                    quit = true;
                }
                else if (keyCode == KeyCode::Space)
                {
                    VR::RecenterTracking();
                    cube.SetEnabled( false );
                    ssao = !ssao;
                }
                else if (keyCode == KeyCode::W)
                {
                    moveDir.z = -velocity;
                }
                else if (keyCode == KeyCode::S)
                {
                    moveDir.z = velocity;
                }
                else if (keyCode == KeyCode::E)
                {
                    moveDir.y = velocity;
                }
                else if (keyCode == KeyCode::Q)
                {
                    moveDir.y = -velocity;
                }
                else if (keyCode == KeyCode::A)
                {
                    moveDir.x = -velocity;
                }
                else if (keyCode == KeyCode::D)
                {
                    moveDir.x = velocity;
                }
                else if (keyCode == KeyCode::Left)
                {
                    camera.GetComponent<TransformComponent>()->OffsetRotate( Vec3( 0, 1, 0 ), 1 );
                    yaw += 4;
                }
                else if (keyCode == KeyCode::Right)
                {
                    camera.GetComponent<TransformComponent>()->OffsetRotate( Vec3( 0, 1, 0 ), -1 );
                    yaw -= 4;
                }
                else if (keyCode == KeyCode::Up)
                {
                    camera.GetComponent<TransformComponent>()->OffsetRotate( Vec3( 1, 0, 0 ), 1 );
                }
                else if (keyCode == KeyCode::Down)
                {
                    camera.GetComponent<TransformComponent>()->OffsetRotate( Vec3( 1, 0, 0 ), -1 );
                }
            }
            else if (event.type == WindowEventType::KeyUp)
            {
                KeyCode keyCode = event.keyCode;

                if (keyCode == KeyCode::W)
                {
                    moveDir.z = 0;
                }
                else if (keyCode == KeyCode::S)
                {
                    moveDir.z = 0;
                }
                else if (keyCode == KeyCode::E)
                {
                    moveDir.y = 0;
                }
                else if (keyCode == KeyCode::Q)
                {
                    moveDir.y = 0;
                }
                else if (keyCode == KeyCode::A)
                {
                    moveDir.x = 0;
                }
                else if (keyCode == KeyCode::D)
                {
                    moveDir.x = 0;
                }
                else if (keyCode == KeyCode::R)
                {
                    reload = true;
                }
            }
            else if (event.type == WindowEventType::MouseMove)
            {
                const int mouseDeltaX = event.mouseX - lastMouseX;
                const int mouseDeltaY = event.mouseY - lastMouseY;
                lastMouseX = event.mouseX;
                lastMouseY = event.mouseY;
                camera.GetComponent<TransformComponent>()->OffsetRotate( Vec3( 0, 1, 0 ), -float( mouseDeltaX ) / 20 );
                camera.GetComponent<TransformComponent>()->OffsetRotate( Vec3( 1, 0, 0 ), float( mouseDeltaY ) / 20 );
            }
            else if (event.type == WindowEventType::GamePadLeftThumbState)
            {           
                gamePadLeftThumbX = event.gamePadThumbX;
                gamePadLeftThumbY = event.gamePadThumbY;
            }
            else if (event.type == WindowEventType::GamePadRightThumbState)
            {
                gamePadRightThumbX = event.gamePadThumbX;
                gamePadRightThumbY = event.gamePadThumbY;
            }
            else if (event.type == WindowEventType::GamePadButtonY)
            {
                camera.GetComponent<TransformComponent>()->MoveUp( 0.1f );
            }
            else if (event.type == WindowEventType::GamePadButtonA)
            {
                camera.GetComponent<TransformComponent>()->MoveUp( -0.1f );
            }
        }

        if (!Window::IsKeyDown( KeyCode::W ) && !Window::IsKeyDown( KeyCode::S ))
        {
            moveDir.z = 0;
        }

        if (!Window::IsKeyDown( KeyCode::A ) && !Window::IsKeyDown( KeyCode::D ))
        {
            moveDir.x = 0;
        }

        if (!Window::IsKeyDown( KeyCode::Q ) && !Window::IsKeyDown( KeyCode::E ))
        {
            moveDir.y = 0;
        }

        camera.GetComponent<TransformComponent>()->MoveUp( moveDir.y );
        camera.GetComponent<TransformComponent>()->MoveForward( moveDir.z );
        camera.GetComponent<TransformComponent>()->MoveRight( moveDir.x );

        camera.GetComponent<TransformComponent>()->MoveForward( -gamePadLeftThumbY );
        camera.GetComponent<TransformComponent>()->MoveRight( gamePadLeftThumbX );
        camera.GetComponent<TransformComponent>()->OffsetRotate( Vec3( 0, 1, 0 ), -float( gamePadRightThumbX ) / 1 );
        camera.GetComponent<TransformComponent>()->OffsetRotate( Vec3( 1, 0, 0 ), float( gamePadRightThumbY ) / 1 );

        static int animationFrame = 0;
        ++animationFrame;
        animatedGo.GetComponent< MeshRendererComponent >()->SetAnimationFrame( animationFrame );

        if (animationFrame % 60 == 0)
        {
            static char statStr[ 512 ] = {};
            System::Statistics::GetStatistics( statStr );
            statsContainer.GetComponent<TextRendererComponent>()->SetText( statStr );
        }
        
#ifdef TEST_FORWARD_PLUS
        static float y = -14;
        y += 0.1f;

        if (y > 30)
        {
            y = -14;
        }

        for (int pointLightIndex = 0; pointLightIndex < POINT_LIGHT_COUNT; ++pointLightIndex)
        {
            const Vec3 oldPos = pointLights[ pointLightIndex ].GetComponent<ae3d::TransformComponent>()->GetLocalPosition();
            const float xOffset = (Random100() % 10) / 20.0f - (Random100() % 10) / 20.0f;
            const float yOffset = (Random100() % 10) / 20.0f - (Random100() % 10) / 20.0f;
            
            pointLights[ pointLightIndex ].GetComponent<ae3d::TransformComponent>()->SetLocalPosition( ae3d::Vec3( oldPos.x + xOffset, -18, oldPos.z + yOffset ) );
        }
#endif
#if defined( AE3D_OPENVR )
        VR::CalcEyePose();
        
        cube.GetComponent< TransformComponent >()->SetLocalPosition( camera.GetComponent< TransformComponent >()->GetWorldPosition() + VR::GetLeftHandPosition() );
        Vec3 pos = VR::GetLeftHandPosition();
        //System::Print( "left hand pos: %f, %f, %f\n", pos.x, pos.y, pos.z );
        camera.GetComponent< CameraComponent >()->SetViewport( 0, 0, width, height );
#else
        if (reload)
        {
            System::Print( "reloading\n" );
            System::ReloadChangedAssets();
            reload = false;
        }
        scene.Render();
#if defined( TEST_MSAA ) && defined( RENDERER_VULKAN )
        cameraTex.ResolveTo( &resolvedTex );
        System::Draw( &resolvedTex, 0, 0, width, height, width, height, Vec4( 1, 1, 1, 1 ), System::BlendMode::Off );
        //System::Draw( &camera2dTex, 0, 0, width, height, width, height, Vec4( 1, 1, 1, 1 ), System::BlendMode::Alpha );
#else
        System::Draw( &cameraTex, 0, 0, width, postHeight, width, postHeight, Vec4( 1, 1, 1, 1 ), System::BlendMode::Off );
        System::Draw( &camera2dTex, 0, 0, width, postHeight, width, postHeight, Vec4( 1, 1, 1, 1 ), System::BlendMode::Alpha );
#endif
#ifdef TEST_BLOOM
#if RENDERER_D3D12
        blurTex.SetLayout( TextureLayout::ShaderReadWrite );

        GpuResource nullResource = {};

        downsampleAndThresholdShader.SetSRV( 0, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() );
        downsampleAndThresholdShader.SetSRV( 1, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        //downsampleAndThresholdShader.SetSRV( 1, nullResource.resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        downsampleAndThresholdShader.SetSRV( 2, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        downsampleAndThresholdShader.SetSRV( 3, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        downsampleAndThresholdShader.SetSRV( 4, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        downsampleAndThresholdShader.SetSRV( 5, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        downsampleAndThresholdShader.SetSRV( 6, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        downsampleAndThresholdShader.SetSRV( 7, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        downsampleAndThresholdShader.SetSRV( 8, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        downsampleAndThresholdShader.SetSRV( 9, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        downsampleAndThresholdShader.SetUAV( 0, blurTex.GetGpuResource()->resource, *blurTex.GetUAVDesc() ); // Unused, but must exist.
        downsampleAndThresholdShader.SetUAV( 1, blurTex.GetGpuResource()->resource, *blurTex.GetUAVDesc() );
#else
        blurTex.SetLayout( TextureLayout::General );

#ifdef TEST_MSAA
        downsampleAndThresholdShader.SetRenderTexture( 0, &resolvedTex );
#else
        downsampleAndThresholdShader.SetRenderTexture( 0, &cameraTex );
#endif
        downsampleAndThresholdShader.SetTexture2D( 14, &blurTex );
#endif
        downsampleAndThresholdShader.Begin();
        downsampleAndThresholdShader.Dispatch( width / 16, height / 16, 1 );
        downsampleAndThresholdShader.End();

        blurTex.SetLayout( TextureLayout::ShaderRead );

        blurShader.SetTexture2D( 0, &blurTex );

#if RENDERER_D3D12
        bloomTex.SetLayout( TextureLayout::ShaderReadWrite );

        blurShader.SetSRV( 1, nullResource.resource, *blurTex.GetSRVDesc() ); // Unused, but must exist
        blurShader.SetSRV( 2, nullResource.resource, *blurTex.GetSRVDesc() ); // Unused, but must exist
        //blurShader.SetSRV( 2, blurTex.GetGpuResource()->resource, *blurTex.GetSRVDesc() ); // Unused, but must exist
        blurShader.SetSRV( 3, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        blurShader.SetSRV( 4, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        blurShader.SetSRV( 5, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        blurShader.SetSRV( 6, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        blurShader.SetSRV( 7, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        blurShader.SetSRV( 8, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        blurShader.SetSRV( 9, cameraTex.GetGpuResource()->resource, *cameraTex.GetSRVDesc() ); // Unused, but must exist
        blurShader.SetUAV( 0, bloomTex.GetGpuResource()->resource, *bloomTex.GetUAVDesc() ); // Unused, but must exist
        blurShader.SetUAV( 1, bloomTex.GetGpuResource()->resource, *bloomTex.GetUAVDesc() );
#else
        blurShader.SetTexture2D( 14, &bloomTex );
#endif
        blurShader.SetUniform( ComputeShader::UniformName::TilesZW, 1, 0 );
        blurShader.Begin();
        blurShader.Dispatch( width / 16, height / 16, 1 );
        blurShader.End();

        blurShader.Begin();

        blurTex.SetLayout( TextureLayout::General );
        bloomTex.SetLayout( TextureLayout::ShaderRead );
        blurShader.SetTexture2D( 0, &bloomTex );

#if RENDERER_D3D12
        blurTex.SetLayout( TextureLayout::ShaderReadWrite );
        blurShader.SetUAV( 1, blurTex.GetGpuResource()->resource, *blurTex.GetUAVDesc() );
#else
        blurShader.SetTexture2D( 14, &blurTex );
#endif
        blurShader.SetUniform( ComputeShader::UniformName::TilesZW, 0, 1 );
        blurShader.Dispatch( width / 16, height / 16, 1 );
        blurShader.End();

#if RENDERER_VULKAN
        // Second blur horizontal begin.
        blurTex.SetLayout( TextureLayout::ShaderRead );
        blurTex2.SetLayout( TextureLayout::General );
        blurShader.SetUniform( ComputeShader::UniformName::TilesZW, 1, 0 );
        blurShader.SetTexture2D( 0, &blurTex );
        blurShader.SetTexture2D( 14, &blurTex2 );
        blurShader.Begin();
        blurShader.Dispatch( width / 16, height / 16, 1 );
        blurShader.End();
        blurTex2.SetLayout( TextureLayout::ShaderRead );
        // Second blur horizontal end.

        // Second blur vertical begin.
        blurTex.SetLayout( TextureLayout::General );
        blurTex2.SetLayout( TextureLayout::ShaderRead );
        blurShader.SetUniform( ComputeShader::UniformName::TilesZW, 0, 1 );
        blurShader.SetTexture2D( 0, &blurTex2 );
        blurShader.SetTexture2D( 14, &blurTex );
        blurShader.Begin();
        blurShader.Dispatch( width / 16, height / 16, 1 );
        blurShader.End();
        // Second blur vertical end.

        // Third blur horizontal begin.
        blurTex.SetLayout( TextureLayout::ShaderRead );
        blurTex2.SetLayout( TextureLayout::General );
        blurShader.SetUniform( ComputeShader::UniformName::TilesZW, 1, 0 );
        blurShader.SetTexture2D( 0, &blurTex );
        blurShader.SetTexture2D( 14, &blurTex2 );
        blurShader.Begin();
        blurShader.Dispatch( width / 16, height / 16, 1 );
        blurShader.End();
        blurTex2.SetLayout( TextureLayout::ShaderRead );
        // Third blur horizontal end.

        // Third blur vertical begin.
        blurTex.SetLayout( TextureLayout::General );
        blurTex2.SetLayout( TextureLayout::ShaderRead );
        blurShader.SetUniform( ComputeShader::UniformName::TilesZW, 0, 1 );
        blurShader.SetTexture2D( 0, &blurTex2 );
        blurShader.SetTexture2D( 14, &blurTex );
        blurShader.Begin();
        blurShader.Dispatch( width / 16, height / 16, 1 );
        blurShader.End();
        // Third blur vertical end.

        // Fourth blur horizontal begin.
        blurTex.SetLayout( TextureLayout::ShaderRead );
        blurTex2.SetLayout( TextureLayout::General );
        blurShader.SetUniform( ComputeShader::UniformName::TilesZW, 1, 0 );
        blurShader.SetTexture2D( 0, &blurTex );
        blurShader.SetTexture2D( 14, &blurTex2 );
        blurShader.Begin();
        blurShader.Dispatch( width / 16, height / 16, 1 );
        blurShader.End();
        blurTex2.SetLayout( TextureLayout::ShaderRead );
        // Fourth blur horizontal end.

        // Fourth blur vertical begin.
        blurTex.SetLayout( TextureLayout::General );
        blurTex2.SetLayout( TextureLayout::ShaderRead );
        blurShader.SetUniform( ComputeShader::UniformName::TilesZW, 0, 1 );
        blurShader.SetTexture2D( 0, &blurTex2 );
        blurShader.SetTexture2D( 14, &blurTex );
        blurShader.Begin();
        blurShader.Dispatch( width / 16, height / 16, 1 );
        blurShader.End();
        // Fourth blur vertical end.
#endif
#if RENDERER_D3D12
        // Second blur horizontal begin.
        /*blurTex.SetLayout( TextureLayout::ShaderRead );
        blurTex2.SetLayout( TextureLayout::ShaderReadWrite );
        blurShader.SetUniform( ComputeShader::UniformName::TilesZW, 1, 0 );
        blurShader.SetTexture2D( 0, &blurTex );
        blurShader.SetUAV( 1, blurTex2.GetGpuResource()->resource, *blurTex2.GetUAVDesc() );

        blurShader.Begin();
        blurShader.Dispatch( width / 16, height / 16, 1 );
        blurShader.End();*/
        //blurTex2.SetLayout( TextureLayout::ShaderRead );
        // Second blur horizontal end.

        // Second blur vertical begin.
        /*blurTex.SetLayout( TextureLayout::ShaderReadWrite );
        blurTex2.SetLayout( TextureLayout::ShaderRead );
        blurShader.SetUniform( ComputeShader::UniformName::TilesZW, 0, 1 );
        blurShader.SetTexture2D( 0, &blurTex2 );
        blurShader.SetUAV( 1, blurTex.GetGpuResource()->resource, *blurTex.GetUAVDesc() );
        blurShader.Begin();
        blurShader.Dispatch( width / 16, height / 16, 1 );
        blurShader.End();*/
        // Second blur vertical end.


#endif
        blurTex.SetLayout( TextureLayout::ShaderRead );
        System::Draw( &cameraTex, 0, 0, width, postHeight, width, postHeight, Vec4( 1, 1, 1, 1 ), System::BlendMode::Off );
        System::Draw( &blurTex, 0, 0, width, postHeight, width, postHeight, Vec4( 1, 1, 1, 0.5f ), System::BlendMode::Additive );
        bloomTex.SetLayout( TextureLayout::General );
#endif // Bloom

#ifdef TEST_SSAO
        if (ssao)
        {
            ssaoTex.SetLayout( TextureLayout::General );
            ssaoShader.SetRenderTexture( 0, &cameraTex );
            ssaoShader.SetRenderTexture( 1, &camera.GetComponent<CameraComponent>()->GetDepthNormalsTexture() );
            ssaoShader.SetTexture2D( 2, &noiseTex );
            ssaoShader.SetTexture2D( 14, &ssaoTex );
            ssaoShader.SetProjectionMatrix( camera.GetComponent<CameraComponent>()->GetProjection() );
            ssaoShader.Begin();
            ssaoShader.Dispatch( width / 8, height / 8, 1 );
            ssaoShader.End();
            ssaoTex.SetLayout( TextureLayout::ShaderRead );

            System::Draw( &ssaoTex, 0, 0, width, postHeight, width, postHeight, Vec4( 1, 1, 1, 1 ), System::BlendMode::Off );
        }
#endif

        scene.EndFrame();
#endif
        
        Window::SwapBuffers();
    }

    for (auto& mat : sponzaMaterialNameToMaterial)
    {
        delete mat.second;
    }
    
    for (Mesh* *it = sponzaMeshes.elements; it != sponzaMeshes.elements + sponzaMeshes.count; ++it)
    {
        delete *it;
    }
    
    for (auto& t : sponzaTextureNameToTexture)
    {
        delete t.second;
    }

    VR::Deinit();
    System::Deinit();
}
