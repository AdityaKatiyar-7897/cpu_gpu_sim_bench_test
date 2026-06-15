// FPS START DROPPING AFTER AROUND 700

#include <SDL.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>


#define WIDTH 1200
#define HEIGHT 800

#define BALL_COUNT 4000
#define TARGET_FPS 60

// Creating the ball
typedef struct
{
    float x;
    float y;

    float vx;
    float vy;

    float radius;

} Ball;


//Simulation logic

void ball_step(Ball *ball, float dt)
{
    const float gravity = 1000.0f;

    /* gravity accelerates downward */
    ball->vy += gravity * dt;

    /* move ball using velocity */
    ball->x += ball->vx * dt;
    ball->y += ball->vy * dt;

    float floor_y = HEIGHT - ball->radius;

    /* collision with floor */
    if (ball->y > floor_y)
    {
        ball->y = floor_y;

        /* bounce upward */
        ball->vy = -ball->vy * 0.75f;

        /* stop tiny endless bouncing */
        if (ball->vy > -10.0f)
        {
            ball->vy = 0.0f;
        }
    }

    if (ball->x < ball->radius)
    {
        ball->x = ball->radius;
        ball->vx = -ball->vx * 0.9f;
    }
    
    if (ball->x > WIDTH - ball->radius)
    {
        ball->x = WIDTH - ball->radius;
        ball->vx = -ball->vx * 0.9f;
    }
}


//Drawing the ball i.r rendering logic


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

void draw_ball(SDL_Renderer *renderer, SDL_Texture *ball_texture, Ball *ball)
{
    int r = (int)ball->radius;

    SDL_Rect rect = {
        (int)ball->x - r,
        (int)ball->y - r,
        r * 2,
        r * 2
    };

    SDL_RenderCopy(renderer, ball_texture, NULL, &rect);
}

// Ball - ball collision check

void ball_collision(Ball *input, Ball *output, int id, int count)
{
    Ball a = input[id];

    for (int j = 0; j < count; j++)
    {
        if (j == id)
        {
            continue;
        }

        Ball b = input[j];

        float dx = a.x - b.x;
        float dy = a.y - b.y;
        float min_distance = a.radius + b.radius;
        float distance_squared = dx * dx + dy * dy;

        if (distance_squared > 0.0001f && distance_squared < min_distance * min_distance)
        {
            float distance = sqrtf(distance_squared);
            float nx = dx / distance;
            float ny = dy / distance;

            float relative_vx = a.vx - b.vx;
            float relative_vy = a.vy - b.vy;
            float velocity_along_normal = relative_vx * nx + relative_vy * ny;

            if (velocity_along_normal < 0.0f)
            {
                a.vx -= velocity_along_normal * nx * 0.8f;
                a.vy -= velocity_along_normal * ny * 0.8f;
            }

            float overlap = min_distance - distance;
            a.x += nx * overlap * 0.25f;
            a.y += ny * overlap * 0.25f;
        }
    }

    output[id] = a;
}


int main(void)
{
   
    SDL_Init(SDL_INIT_VIDEO);

    SDL_Window *window =
        SDL_CreateWindow(
            "Ball Simulation",
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

    


    // Introducing more balls 
    
    Ball balls[BALL_COUNT];
    Ball collision_input[BALL_COUNT];

    //Spawning many balls

    for (int i = 0; i < BALL_COUNT; i++)
    {
    	balls[i].x = 50 + rand() % (WIDTH - 100);

    	balls[i].y = -(rand() % 2000);

    	balls[i].vx = (rand() % 200) - 100; //to make them move left right while falling 
    	balls[i].vy = 0.0f;

    	balls[i].radius = 8.0f;
    }
        
    bool running = true;

    Uint64 previous =
        SDL_GetPerformanceCounter();

    float fps_timer = 0.0f;
    int frames = 0;
    float fps = 0.0f;

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
            {
                running = false;
            }
        }
              
        Uint64 current =
            SDL_GetPerformanceCounter();

        float dt =
            (float)(current - previous)
            / SDL_GetPerformanceFrequency();

        previous = current;

        fps_timer += dt;
        frames++;

        if (fps_timer >= 0.5f)
        {
            fps = frames / fps_timer;

            char title[128];

            snprintf(
                title,
                sizeof(title),
                "Balls: %d | FPS: %.1f",
                BALL_COUNT,
                fps
            );

            SDL_SetWindowTitle(window, title);

            fps_timer = 0.0f;
            frames = 0;
        }
      
        for (int i= 0; i < BALL_COUNT; i++)
        {
        	ball_step(&balls[i], dt);
        }

        memcpy(collision_input, balls, sizeof(balls));

        // Every ball checks every other ball using the same pre-collision snapshot.
        for (int i = 0; i < BALL_COUNT; i++)
        {
            ball_collision(
                collision_input,
                balls,
                i,
                BALL_COUNT
            );
        }
              
        SDL_SetRenderDrawColor(
            renderer,
            20,
            20,
            20,
            255);

        SDL_RenderClear(renderer);

        SDL_SetRenderDrawColor(
            renderer,
            255,
            255,
            255,
            255);

        for (int i = 0; i < BALL_COUNT; i++)
        {
            draw_ball(renderer, ball_texture, &balls[i]);

           
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
    }
    
    SDL_DestroyTexture(ball_texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);

    SDL_Quit();

    return 0;
}
