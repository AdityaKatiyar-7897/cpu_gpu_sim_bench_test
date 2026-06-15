#include <SDL.h>
#include <Metal/Metal.h>
#include <Foundation/Foundation.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#define WIDTH 1200
#define HEIGHT 800
#define BALL_COUNT 40000
#define TARGET_FPS 60

typedef struct
{
    float x;
    float y;
    float vx;
    float vy;
    float radius;
} Ball;

static const char *metal_source = R"(
#include <metal_stdlib>
using namespace metal;

struct Ball
{
    float x;
    float y;
    float vx;
    float vy;
    float radius;
};

kernel void step_balls(
    device const Ball *input [[buffer(0)]],
    device Ball *stepped [[buffer(1)]],
    constant float &dt [[buffer(2)]],
    constant uint &count [[buffer(3)]],
    uint id [[thread_position_in_grid]])
{
    if (id >= count)
        return;

    Ball ball = input[id];

    float gravity = 1000.0;

    ball.vy += gravity * dt;
    ball.x += ball.vx * dt;
    ball.y += ball.vy * dt;

    float floor_y = 800.0 - ball.radius;

    if (ball.y > floor_y)
    {
        ball.y = floor_y;
        ball.vy = -ball.vy * 0.75;

        if (ball.vy > -10.0)
            ball.vy = 0.0;
    }

    if (ball.x < ball.radius)
    {
        ball.x = ball.radius;
        ball.vx = -ball.vx * 0.9;
    }

    if (ball.x > 1200.0 - ball.radius)
    {
        ball.x = 1200.0 - ball.radius;
        ball.vx = -ball.vx * 0.9;
    }

    stepped[id] = ball;
}

kernel void collide_balls(
    device const Ball *input [[buffer(0)]],
    device Ball *output [[buffer(1)]],
    constant uint &count [[buffer(2)]],
    uint id [[thread_position_in_grid]])
{
    if (id >= count)
        return;

    Ball a = input[id];

    for (uint j = 0; j < count; j++)
    {
        if (j == id)
            continue;

        Ball b = input[j];

        float dx = a.x - b.x;
        float dy = a.y - b.y;
        float min_distance = a.radius + b.radius;
        float distance_squared = dx * dx + dy * dy;

        if (distance_squared > 0.0001 && distance_squared < min_distance * min_distance)
        {
            float distance = sqrt(distance_squared);
            float nx = dx / distance;
            float ny = dy / distance;

            float relative_vx = a.vx - b.vx;
            float relative_vy = a.vy - b.vy;
            float velocity_along_normal = relative_vx * nx + relative_vy * ny;

            if (velocity_along_normal < 0.0)
            {
                a.vx -= velocity_along_normal * nx * 0.8;
                a.vy -= velocity_along_normal * ny * 0.8;
            }

            float overlap = min_distance - distance;
            a.x += nx * overlap * 0.25;
            a.y += ny * overlap * 0.25;
        }
    }

    output[id] = a;
}
)";

SDL_Texture *create_ball_texture(SDL_Renderer *renderer, int radius)
{
    int size = radius * 2;

    SDL_Surface *surface =
        SDL_CreateRGBSurfaceWithFormat(
            0,
            size,
            size,
            32,
            SDL_PIXELFORMAT_RGBA32);

    Uint32 transparent =
        SDL_MapRGBA(surface->format, 0, 0, 0, 0);

    Uint32 white =
        SDL_MapRGBA(surface->format, 255, 255, 255, 255);

    SDL_FillRect(surface, NULL, transparent);

    Uint32 *pixels = (Uint32 *)surface->pixels;

    for (int y = 0; y < size; y++)
    {
        for (int x = 0; x < size; x++)
        {
            int dx = x - radius;
            int dy = y - radius;

            if (dx * dx + dy * dy <= radius * radius)
            {
                pixels[y * size + x] = white;
            }
        }
    }

    SDL_Texture *texture =
        SDL_CreateTextureFromSurface(renderer, surface);

    SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);

    SDL_FreeSurface(surface);

    return texture;
}

void draw_ball(SDL_Renderer *renderer, SDL_Texture *texture, Ball *ball)
{
    int r = (int)ball->radius;

    SDL_Rect rect =
    {
        (int)ball->x - r,
        (int)ball->y - r,
        r * 2,
        r * 2
    };

    SDL_RenderCopy(renderer, texture, NULL, &rect);
}

int main(void)
{
    @autoreleasepool
    {
        SDL_Init(SDL_INIT_VIDEO);

        SDL_Window *window =
            SDL_CreateWindow(
                "GPU Collision Ball Simulation",
                SDL_WINDOWPOS_CENTERED,
                SDL_WINDOWPOS_CENTERED,
                WIDTH,
                HEIGHT,
                0);

        SDL_Renderer *renderer =
            SDL_CreateRenderer(
                window,
                -1,
                SDL_RENDERER_ACCELERATED);

        SDL_Texture *ball_texture =
            create_ball_texture(renderer, 8);

        id<MTLDevice> device =
            MTLCreateSystemDefaultDevice();

        if (!device)
        {
            printf("No Metal GPU found.\n");
            return 1;
        }

        NSError *error = nil;

        id<MTLLibrary> library =
            [device newLibraryWithSource:
                        [NSString stringWithUTF8String:metal_source]
                                    options:nil
                                      error:&error];

        if (!library)
        {
            printf("Metal compile error: %s\n",
                   [[error localizedDescription] UTF8String]);
            return 1;
        }

        id<MTLFunction> step_function =
            [library newFunctionWithName:@"step_balls"];

        id<MTLFunction> collide_function =
            [library newFunctionWithName:@"collide_balls"];

        id<MTLComputePipelineState> step_pipeline =
            [device newComputePipelineStateWithFunction:step_function
                                                   error:&error];

        if (!step_pipeline)
        {
            printf("Step pipeline error: %s\n",
                   [[error localizedDescription] UTF8String]);
            return 1;
        }

        id<MTLComputePipelineState> collide_pipeline =
            [device newComputePipelineStateWithFunction:collide_function
                                                   error:&error];

        if (!collide_pipeline)
        {
            printf("Collision pipeline error: %s\n",
                   [[error localizedDescription] UTF8String]);
            return 1;
        }

        id<MTLCommandQueue> queue =
            [device newCommandQueue];

        Ball *balls =
            (Ball *)malloc(sizeof(Ball) * BALL_COUNT);

        for (int i = 0; i < BALL_COUNT; i++)
        {
            balls[i].x = 50 + rand() % (WIDTH - 100);
            balls[i].y = -(rand() % 2000);
            balls[i].vx = (rand() % 200) - 100;
            balls[i].vy = 0.0f;
            balls[i].radius = 8.0f;
        }

        id<MTLBuffer> ball_buffer =
            [device newBufferWithBytes:balls
                                 length:sizeof(Ball) * BALL_COUNT
                                options:MTLResourceStorageModeShared];

        id<MTLBuffer> temp_buffer =
            [device newBufferWithLength:sizeof(Ball) * BALL_COUNT
                                options:MTLResourceStorageModeShared];

        free(balls);

        bool running = true;

        Uint64 previous =
            SDL_GetPerformanceCounter();

        float fps_timer = 0.0f;
        int frames = 0;
        float fps = 0.0f;
        float gpu_ms = 0.0f;

        const double counter_frequency =
            (double)SDL_GetPerformanceFrequency();

        const double target_frame_seconds =
            1.0 / TARGET_FPS;

        while (running)
        {
            Uint64 frame_start =
                SDL_GetPerformanceCounter();

            SDL_Event event;

            while (SDL_PollEvent(&event))
            {
                if (event.type == SDL_QUIT)
                    running = false;
            }

            Uint64 current =
                SDL_GetPerformanceCounter();

            float dt =
                (float)(current - previous) /
                SDL_GetPerformanceFrequency();

            previous = current;

            if (dt > 0.033f)
                dt = 0.033f;

            unsigned int count = BALL_COUNT;

            Uint64 gpu_start =
                SDL_GetPerformanceCounter();

            id<MTLCommandBuffer> command_buffer =
                [queue commandBuffer];

            id<MTLComputeCommandEncoder> encoder =
                [command_buffer computeCommandEncoder];

            MTLSize grid =
                MTLSizeMake(BALL_COUNT, 1, 1);

            MTLSize group =
                MTLSizeMake(256, 1, 1);

            [encoder setComputePipelineState:step_pipeline];

            [encoder setBuffer:ball_buffer
                         offset:0
                        atIndex:0];

            [encoder setBuffer:temp_buffer
                         offset:0
                        atIndex:1];

            [encoder setBytes:&dt
                        length:sizeof(float)
                       atIndex:2];

            [encoder setBytes:&count
                        length:sizeof(unsigned int)
                       atIndex:3];

            [encoder dispatchThreads:grid
                threadsPerThreadgroup:group];

            [encoder setComputePipelineState:collide_pipeline];

            [encoder setBuffer:temp_buffer
                         offset:0
                        atIndex:0];

            [encoder setBuffer:ball_buffer
                         offset:0
                        atIndex:1];

            [encoder setBytes:&count
                        length:sizeof(unsigned int)
                       atIndex:2];

            [encoder dispatchThreads:grid
                threadsPerThreadgroup:group];

            [encoder endEncoding];

            [command_buffer commit];
            [command_buffer waitUntilCompleted];

            Uint64 gpu_end =
                SDL_GetPerformanceCounter();

            gpu_ms =
                (float)((gpu_end - gpu_start) * 1000.0 / counter_frequency);

            Ball *gpu_balls =
                (Ball *)[ball_buffer contents];

            SDL_SetRenderDrawColor(renderer, 20, 20, 20, 255);
            SDL_RenderClear(renderer);

            for (int i = 0; i < BALL_COUNT; i++)
            {
                draw_ball(renderer, ball_texture, &gpu_balls[i]);
            }

            SDL_RenderPresent(renderer);

            while ((SDL_GetPerformanceCounter() - frame_start) / counter_frequency < target_frame_seconds)
            {
                double elapsed =
                    (SDL_GetPerformanceCounter() - frame_start) / counter_frequency;

                double remaining =
                    target_frame_seconds - elapsed;

                if (remaining > 0.002)
                    SDL_Delay((Uint32)(remaining * 1000.0) - 1);
                else
                    SDL_Delay(0);
            }

            fps_timer += dt;
            frames++;

            if (fps_timer >= 0.5f)
            {
                fps = frames / fps_timer;

                char title[160];

                snprintf(
                    title,
                    sizeof(title),
                    "GPU Collision | Balls: %d | FPS: %.1f | GPU: %.2f ms",
                    BALL_COUNT,
                    fps,
                    gpu_ms);

                SDL_SetWindowTitle(window, title);

                fps_timer = 0.0f;
                frames = 0;
            }
        }

        SDL_DestroyTexture(ball_texture);
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
        SDL_Quit();
    }

    return 0;
}
