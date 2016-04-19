#ifndef RENDERER_H
#define RENDERER_H

#include "Shader.hpp"
#include "VertexBuffer.hpp"

namespace ae3d
{
    class TextureCube;
    class CameraComponent;
    
    struct BuiltinShaders
    {
        void Load();
        
        Shader spriteRendererShader;
        Shader sdfShader;
        Shader skyboxShader;
        Shader momentsShader;
        Shader depthNormalsShader;
    };

    /// High-level rendering stuff.
    class Renderer
    {
    public:
        /// \return True if skybox has been generated.
        bool IsSkyboxGenerated() const { return skyboxBuffer.IsGenerated(); }
        
        void GenerateSkybox();

        void RenderSkybox( TextureCube* skyTexture, const CameraComponent& camera );

        BuiltinShaders builtinShaders;
        
    private:
        VertexBuffer skyboxBuffer;
    };    
}

#endif
