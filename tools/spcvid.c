// This is released into the public domain.
// No warranty is provided, implied or otherwise.
//
// Screen-displayer application for Space Invaders emulator,
//  by 20kdc
// Might be a bit broken
//
// Compile with:
// gcc -lSDL -o spcvid spcvid.c

#include <SDL/SDL.h>
#include <SDL/SDL_keysym.h>
#include <unistd.h>

static char main_videodata[7168];

// Change these 3 to 1 to disable colour overlay
#define COLOUR_WHITE 1
#define COLOUR_RED 2
#define COLOUR_GREEN 3

#define COLOUR_COUNT 4
static SDL_Color colourmap[COLOUR_COUNT] = {
	{0, 0, 0},
	{255, 255, 255},
	{255, 0, 0},
	{0, 255, 0},
};

static void push_input(Uint8 * a, Uint8 * b) {
	write(1, a, 1);
	write(1, b, 1);
}

static void pull_video() {
	size_t wanted = 7168;
	char * point = main_videodata;
	while (wanted) {
		ssize_t p = read(0, point, wanted);
		if (p < 1)
			return;
		wanted -= p;
		point += p;
	}
}

static int get_video_colour(int x, int y) {
	if (y >= 32) {
		if (y < 64)
			return COLOUR_RED;
		if (y >= 184) {
			if (y >= 240) {
				if ((x >= 16) && (x < 134))
					return COLOUR_GREEN;
				return COLOUR_RED;
			}
			return COLOUR_GREEN;
		}
	}
	return COLOUR_WHITE;
}

static void submit_video_char(int x, int y, Uint8 * px, char c) {
	for (int i = 0; i < 8; i++) {
		px[x + (y * 224)] = c & 1 ? get_video_colour(x, y) : 0;
		c >>= 1;
		y--;
	}
}

static void submit_video(SDL_Surface * video) {
	SDL_LockSurface(video);
	Uint8 * px = video->pixels;
	for (int i = 0; i < 7168; i++) {
		int x = i >> 5;
		int y = 255 - ((i & 31) << 3);
		submit_video_char(x, y, px, main_videodata[i]);
	}
	SDL_UnlockSurface(video);
	SDL_Flip(video);
}

int main(int argc, char ** argv) {

	// start SDL
	if (SDL_Init(SDL_INIT_EVERYTHING))
		return 1;
	SDL_Surface * video = SDL_SetVideoMode(224, 256, 8, 0);

	// prep. palette
	SDL_SetColors(video, colourmap, 0, COLOUR_COUNT);

	// main loop. boring.
	int running = 1;
	int time = SDL_GetTicks();
	Uint8 buttons1 = 1;
	Uint8 buttons2 = 0;
	while (running) {
		while (SDL_GetTicks() < time)
			SDL_Delay(5);
		time += (1000 / 60);
		SDL_Event se;
		while (SDL_PollEvent(&se)) {
			if ((se.type == SDL_KEYDOWN) || (se.type == SDL_KEYUP)) {
				int mask1 = 0;
				int mask2 = 0;
				switch (se.key.keysym.sym) {
					case SDLK_c:
						mask1 = 1; // COIN
						break;
					case SDLK_x:
						mask1 = 2; // P2 Start
						break;
					case SDLK_z:
						mask1 = 4; // P1 Start
						break;
					case SDLK_s:
						mask1 = 16; // P1 Fire
						break;
					case SDLK_a:
						mask1 = 32; // P1 Left
						break;
					case SDLK_d:
						mask1 = 64; // P1 Right
						break;

					case SDLK_t:
						mask2 = 4; // TILT
						break;
					case SDLK_k:
						mask2 = 16; // P2 Fire
						break;
					case SDLK_j:
						mask2 = 32; // P2 Left
						break;
					case SDLK_l:
						mask2 = 64; // P2 Right
						break;
				}
				if (mask1) {
					int v = (se.type == SDL_KEYDOWN) ^ (mask1 == 1);
					if (v) {
						buttons1 |= mask1;
					} else {
						buttons1 &= ~mask1;
					}
				} else {
					if (se.type == SDL_KEYDOWN) {
						buttons2 |= mask2;
					} else {
						buttons2 &= ~mask2;
					}
				}
			}
			if (se.type == SDL_QUIT)
				running = 0;
		}
		push_input(&buttons1, &buttons2);
		pull_video();
		submit_video(video);
	}
	SDL_Quit();
	return 0;
}
