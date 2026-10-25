using System.Numerics;

using Oxylus;

namespace Pong;

delegate void Edit<T>(ref T value);

// the entities a match is played with
static class Arena
{
    public static Entity SpawnBackground(World world) =>
        world.Spawn("background")
            .Place(new Vector3(0.0f, 0.0f, -1.0f), new Vector3(24.0f, 18.0f, 0.5f))
            .WithSprite("Sprites/space_background.png");

    public static Entity SpawnPaddle(World world, string name, float x) =>
        world.Spawn(name)
            .Place(new Vector3(x, 0.0f, 0.0f), new Vector3(0.5f, 2.0f * Tuning.PaddleHalfHeight, 1.0f))
            .WithSprite("Sprites/player.png")
            .With((ref BoxColliderComponent collider) =>
            {
                collider.Size = new Vector3(0.25f, Tuning.PaddleHalfHeight, 0.25f);
                collider.Friction = 0.0f;
                collider.Restitution = 1.0f;
            })
            .With((ref RigidBodyComponent body) =>
            {
                body.Type = RigidBodyType.Kinematic;
                Frictionless(ref body);
            });

    public static Entity SpawnBall(World world) =>
        world.Spawn("ball")
            .Place(Vector3.Zero, new Vector3(2.0f * Tuning.BallRadius))
            .WithSprite("Sprites/ball.png")
            .With((ref SphereColliderComponent collider) =>
            {
                collider.Radius = Tuning.BallRadius;
                collider.Friction = 0.0f;
                collider.Restitution = 1.0f;
            })
            .With((ref RigidBodyComponent body) =>
            {
                body.Type = RigidBodyType.Dynamic;
                body.AllowedDofs = AllowedDofs.TranslationX | AllowedDofs.TranslationY;
                Frictionless(ref body);
            });

    public static Entity SpawnWall(World world, string name, float y) =>
        world.Spawn(name)
            .Place(new Vector3(0.0f, y, 0.0f), Vector3.One)
            .With((ref BoxColliderComponent collider) =>
            {
                collider.Size = new Vector3(10.0f, Tuning.WallHalfThickness, 1.0f);
                collider.Friction = 0.0f;
                collider.Restitution = 1.0f;
            })
            .With((ref RigidBodyComponent body) =>
            {
                body.Type = RigidBodyType.Static;
                Frictionless(ref body);
            });

    // nothing slows the game down: the ball keeps its speed through every bounce, and the paddles never sleep
    static void Frictionless(ref RigidBodyComponent body)
    {
        body.GravityFactor = 0.0f;
        body.Friction = 0.0f;
        body.Restitution = 1.0f;
        body.LinearDrag = 0.0f;
        body.AngularDrag = 0.0f;
        body.AllowSleep = false;
        body.Continuous = true;
    }

    static Entity Place(this Entity entity, Vector3 position, Vector3 scale)
    {
        ref var transform = ref entity.Get<TransformComponent>();
        transform.Position = position;
        transform.Scale = scale;
        entity.Modified<TransformComponent>();
        return entity;
    }

    // starts from the component's defaults, so only what differs is set
    static Entity With<T>(this Entity entity, Edit<T> edit) where T : unmanaged
    {
        edit(ref entity.Ensure<T>());
        entity.Modified<T>();
        return entity;
    }

    // the sprite's material holds the texture, so nothing else has to
    static Entity WithSprite(this Entity entity, string texture)
    {
        var material = entity.Ensure<SpriteComponent>().Material;
        Assets.GetMaterial(material, out var data);
        data.AlbedoTexture = Assets.Find(texture);
        data.SamplingMode = SamplingMode.NearestClamped;
        Assets.SetMaterial(material, data);
        return entity;
    }
}
