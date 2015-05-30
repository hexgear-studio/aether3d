#ifndef SCENE_H
#define SCENE_H

#include <vector>

namespace ae3d
{
    class GameObject;
    class CameraComponent;

    /// Contains game objects in a transform hierarchy.
    class Scene
    {
    public:
        /** Adds a game object into the scene if it does not exist there already. */
        void Add( GameObject* gameObject );

        /** Renders the scene. */
        void Render();

    private:
        void RenderWithCamera( CameraComponent* camera );

        std::vector< GameObject* > gameObjects;
        GameObject* mainCamera = nullptr;
        unsigned nextFreeGameObject = 0;
    };
}
#endif
