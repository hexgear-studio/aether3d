#include "MeshRendererComponent.hpp"
#include <vector>
#include "Frustum.hpp"
#include "Matrix.hpp"
#include "Mesh.hpp"
#include "GfxDevice.hpp"
#include "Material.hpp"
#include "VertexBuffer.hpp"
#include "SubMesh.hpp"
#include "Vec3.hpp"

using namespace ae3d;

namespace MathUtil
{
    void GetMinMax( const std::vector< Vec3 >& aPoints, Vec3& outMin, Vec3& outMax )
    {
        if (!aPoints.empty())
        {
            outMin = aPoints[ 0 ];
            outMax = aPoints[ 0 ];
        }
        
        for (std::size_t i = 1; i < aPoints.size(); ++i)
        {
            if (aPoints[ i ].x < outMin.x)
            {
                outMin.x = aPoints[ i ].x;
            }
            
            if (aPoints[ i ].y < outMin.y)
            {
                outMin.y = aPoints[ i ].y;
            }
            
            if (aPoints[ i ].z < outMin.z)
            {
                outMin.z = aPoints[ i ].z;
            }
            
            if (aPoints[ i ].x > outMax.x)
            {
                outMax.x = aPoints[ i ].x;
            }
            
            if (aPoints[ i ].y > outMax.y)
            {
                outMax.y = aPoints[ i ].y;
            }
            
            if (aPoints[ i ].z > outMax.z)
            {
                outMax.z = aPoints[ i ].z;
            }
        }
    }
    
    void GetCorners( const Vec3& min, const Vec3& max, std::vector< Vec3 >& outCorners )
    {
        outCorners =
        {
            Vec3( min.x, min.y, min.z ),
            Vec3( max.x, min.y, min.z ),
            Vec3( min.x, max.y, min.z ),
            Vec3( min.x, min.y, max.z ),
            Vec3( max.x, max.y, min.z ),
            Vec3( min.x, max.y, max.z ),
            Vec3( max.x, max.y, max.z ),
            Vec3( max.x, min.y, max.z )
        };
    }
}

std::vector< ae3d::MeshRendererComponent > meshRendererComponents;
unsigned nextFreeMeshRendererComponent = 0;

unsigned ae3d::MeshRendererComponent::New()
{
    if (nextFreeMeshRendererComponent == meshRendererComponents.size())
    {
        meshRendererComponents.resize( meshRendererComponents.size() + 10 );
    }
    
    return nextFreeMeshRendererComponent++;
}

ae3d::MeshRendererComponent* ae3d::MeshRendererComponent::Get( unsigned index )
{
    return &meshRendererComponents[index];
}

void ae3d::MeshRendererComponent::Render( const Matrix44& modelViewProjection, const Frustum& cameraFrustum, const Matrix44& localToWorld )
{
    std::vector< Vec3 > aabbWorld;
    MathUtil::GetCorners( mesh->GetAABBMin(), mesh->GetAABBMax(), aabbWorld );
    
    for (std::size_t v = 0; v < aabbWorld.size(); ++v)
    {
        Matrix44::TransformPoint( aabbWorld[ v ], localToWorld, &aabbWorld[ v ] );
    }
    
    Vec3 aabbMinWorld, aabbMaxWorld;
    MathUtil::GetMinMax( aabbWorld, aabbMinWorld, aabbMaxWorld );

    std::vector< SubMesh >& subMeshes = mesh->GetSubMeshes();

    if (!cameraFrustum.BoxInFrustum( aabbMinWorld, aabbMaxWorld ))
    {
        return;
    }

    for (std::size_t subMeshIndex = 0; subMeshIndex < subMeshes.size(); ++subMeshIndex)
    {
        if (materials[ subMeshIndex ] == nullptr || !materials[ subMeshIndex ]->IsValidShader())
        {
            continue;
        }
        
        Vec3 meshAabbMinWorld = subMeshes[ subMeshIndex ].aabbMin;
        Vec3 meshAabbMaxWorld = subMeshes[ subMeshIndex ].aabbMax;
        
        std::vector< Vec3 > meshAabbWorld;
        MathUtil::GetCorners( meshAabbMinWorld, meshAabbMaxWorld, meshAabbWorld );
        
        for (std::size_t v = 0; v < meshAabbWorld.size(); ++v)
        {
            Matrix44::TransformPoint( meshAabbWorld[ v ], localToWorld, &meshAabbWorld[ v ] );
        }
        
        MathUtil::GetMinMax( meshAabbWorld, meshAabbMinWorld, meshAabbMaxWorld );

        if (!cameraFrustum.BoxInFrustum( meshAabbMinWorld, meshAabbMaxWorld ))
        {
            continue;
        }
        
        GfxDevice::SetBlendMode( ae3d::GfxDevice::BlendMode::Off );

        materials[ subMeshIndex ]->SetMatrix( "_ModelViewProjectionMatrix", modelViewProjection );
        materials[ subMeshIndex ]->Apply();
        
        subMeshes[ subMeshIndex ].vertexBuffer.Bind();
        subMeshes[ subMeshIndex ].vertexBuffer.Draw();
    }
}

void ae3d::MeshRendererComponent::SetMaterial( Material* material, int subMeshIndex )
{
    if (subMeshIndex >= 0 && subMeshIndex < int( materials.size() ))
    {
        materials[ subMeshIndex ] = material;
    }
}

void ae3d::MeshRendererComponent::SetMesh( Mesh* aMesh )
{
    mesh = aMesh;

    if (mesh != nullptr)
    {
        materials.resize( mesh->GetSubMeshes().size() );
    }
}