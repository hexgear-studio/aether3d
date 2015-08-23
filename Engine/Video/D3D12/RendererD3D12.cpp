#include "Renderer.hpp"
#include <string>
#include "System.hpp"

ae3d::Renderer renderer;

void ae3d::BuiltinShaders::Load()
{
    const std::string source(
        "struct VSOutput\
{\
    float4 pos : SV_POSITION;\
    float4 color : COLOR;\
    };\
cbuffer Scene\
    {\
        float4x4 mvp;\
    };\
    VSOutput VSMain( float3 pos : POSITION, float2 uv : TEXCOORD, float4 color : COLOR )\
    {\
        VSOutput vsOut;\
        vsOut.pos = mul( mvp, float4( pos, 1.0 ) );\
        vsOut.color = color;\
        return vsOut;\
    }\
    float4 PSMain( VSOutput vsOut ) : SV_Target\
    {\
        return float4(0.0, 1.0, 0.0, 1.0);\
    }"
        );

    spriteRendererShader.Load( source.c_str(), source.c_str() );
    sdfShader.Load( source.c_str(), source.c_str() );
    skyboxShader.Load( source.c_str(), source.c_str() );
}