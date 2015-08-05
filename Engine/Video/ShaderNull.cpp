#include "Shader.hpp"
#include "System.hpp"
#include "Texture2D.hpp"

void ae3d::Shader::Load( const char* vertexSource, const char* fragmentSource )
{
}

void ae3d::Shader::Use()
{
}

void ae3d::Shader::SetMatrix( const char* name, const float* matrix4x4 )
{
}

void ae3d::Shader::SetTexture( const char* name, const ae3d::Texture2D* texture, int textureUnit )
{
}

void ae3d::Shader::SetInt( const char* name, int value )
{
}

void ae3d::Shader::SetFloat( const char* name, float value )
{
}

void ae3d::Shader::SetVector3( const char* name, const float* vec3 )
{
}

void ae3d::Shader::SetVector4( const char* name, const float* vec4 )
{
}