#include <SDL.h>
#include <stdbool.h>

#define WIDTH 1200
#define HEIGHT 800

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
}


//Drawing the ball i.r rendering logic


void draw_ball(SDL_Renderer *renderer, Ball *ball)
{
    SDL_SetRenderDrawColor(
        renderer,
        255,
        255,
        255,
        255);

    int r = (int)ball->radius;

    for (int y = -r; y <= r; y++)
    {
        for (int x = -r; x <= r; x++)
        {
            if (x*x + y*y <= r*r)
            {
                SDL_RenderDrawPoint(
                    renderer,
                    (int)ball->x + x,
                    (int)ball->y + y);
            }
        }
    }
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


    // Creating one ball
    Ball ball =
    {
        .x = WIDTH / 2.0f,
        .y = 100.0f,

        .vx = 0.0f,
        .vy = 0.0f,

        .radius = 20.0f
    };


    bool running = true;

    Uint64 previous =
        SDL_GetPerformanceCounter();


        while (running)
    {
       
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
      
        ball_step(&ball, dt);
              
        SDL_SetRenderDrawColor(
            renderer,
            20,
            20,
            20,
            255);

        SDL_RenderClear(renderer);

        draw_ball(renderer, &ball);

        SDL_RenderPresent(renderer);
    }
    
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);

    SDL_Quit();

    return 0;
}
