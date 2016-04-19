#ifndef TEXTURE_2D_H
#define TEXTURE_2D_H

#include "Vec3.hpp"
#include "TextureBase.hpp"
#if RENDERER_VULKAN
#include <vulkan/vulkan.h>
#endif

namespace ae3d
{
    namespace FileSystem
    {
        struct FileContentsData;
    }

    /// 2D texture.
    class Texture2D : public TextureBase
    {
    public:
        /// Gets a default texture that is always available after System::LoadBuiltinAssets().
        static Texture2D* GetDefaultTexture();
        
        /// \param textureData Texture image data. File format must be dds, png, tga, jpg, bmp or bmp.
        /// \param wrap Wrap mode.
        /// \param filter Filter mode.
        /// \param mipmaps Mipmaps
        /// \param colorSpace Color space.
        /// \param anisotropy Anisotropy. Value range is 1-16 depending on support.
        void Load( const FileSystem::FileContentsData& textureData, TextureWrap wrap, TextureFilter filter, Mipmaps mipmaps, ColorSpace colorSpace, float anisotropy );
        
        /// \param atlasTextureData Atlas texture image data. File format must be dds, png, tga, jpg, bmp or bmp.
        /// \param atlasMetaData Atlas metadata. Format is Ogre/CEGUI. Example atlas tool: Texture Packer.
        /// \param textureName Name of the texture in atlas.
        /// \param wrap Wrap mode.
        /// \param filter Filter mode.
        /// \param colorSpace Color space.
        /// \param anisotropy Anisotropy. Value range is 1-16 depending on support.
        void LoadFromAtlas( const FileSystem::FileContentsData& atlasTextureData, const FileSystem::FileContentsData& atlasMetaData, const char* textureName, TextureWrap wrap, TextureFilter filter, ColorSpace colorSpace, float anisotropy );

#if RENDERER_VULKAN
        VkImageView& GetView() { return view; }
#endif
#if RENDERER_D3D12
        static void DestroyTextures();
#endif

    private:
        /// \param path Path.
        void LoadDDS( const char* path );
        
        /**
          Loads texture from stb_image.c supported formats.

          \param textureData Texture data.
          */
        void LoadSTB( const FileSystem::FileContentsData& textureData );
#if RENDERER_METAL
        void LoadPVRv2( const char* path );
        void LoadPVRv3( const char* path );
#endif
#if RENDERER_VULKAN
        VkImage image = VK_NULL_HANDLE;
        VkImageView view = VK_NULL_HANDLE;
        VkDeviceMemory deviceMemory = VK_NULL_HANDLE;
#endif
    };
}
#endif
