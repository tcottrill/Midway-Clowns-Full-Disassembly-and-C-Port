/* plat_win.c - the Windows backend of the Clowns C port: one window, a GDI
 * blit of the game's 256 x 224 bitmap, waveOut audio, mouse and keyboard.
 * Plain Win32, no other libraries.  Settings in clowns_win.ini beside the exe.
 *
 * Keys:  mouse X / Left / Right  the paddle (both players)
 *        5 coin   1 one-player start   2 two-player start
 *        F2 self-test switch (latched; the ROM reads it at reset)
 *        F3 reset (power cycle)   Esc quit
 *
 * Command line:
 *        --test                  self-test switch on at power-on
 *        --scale N               window scale (1-6)
 *        --hidden                never show the window (scripts)
 *        --quit-after-frames N   run N frames and exit
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../clowns_platform.h"
#include "../../sound.h"

#define AUDIO_BUFFERS   8
#define AUDIO_SAMPLES   1024
#define AUDIO_MAX_AHEAD 5          /* buffers queued before new audio is dropped */

static HWND      hwnd;
static uint32_t  pixels[PLAT_VIDEO_W * PLAT_VIDEO_H];
static BITMAPINFO bmi;
static int       cfg_scale = 3, cfg_hidden, cfg_test, cfg_volume = 60;
static int       cfg_key_speed = 4, cfg_mouse = 1;
static uint8_t   cfg_dsw;
static long      cfg_quit_frames = -1;
static int       quit_flag, test_switch, reset_request;
static int       paddle = 0x7F;
static char      ini_path[MAX_PATH];

/* ---- audio -------------------------------------------------------------- */
static HWAVEOUT  wave;
static WAVEHDR   hdr[AUDIO_BUFFERS];
static int16_t   abuf[AUDIO_BUFFERS][AUDIO_SAMPLES];
static int       acur, afill;
static volatile LONG aqueued;

static void CALLBACK wave_cb(HWAVEOUT h, UINT msg, DWORD_PTR inst, DWORD_PTR p1, DWORD_PTR p2)
{
    (void)h; (void)inst; (void)p1; (void)p2;
    if (msg == WOM_DONE) InterlockedDecrement(&aqueued);
}

int plat_audio_open(int sample_rate)
{
    WAVEFORMATEX wf;
    int i;
    memset(&wf, 0, sizeof wf);
    wf.wFormatTag = WAVE_FORMAT_PCM;
    wf.nChannels = 1;
    wf.nSamplesPerSec = (DWORD)sample_rate;
    wf.wBitsPerSample = 16;
    wf.nBlockAlign = 2;
    wf.nAvgBytesPerSec = (DWORD)sample_rate * 2;
    if (waveOutOpen(&wave, WAVE_MAPPER, &wf, (DWORD_PTR)wave_cb, 0, CALLBACK_FUNCTION) != MMSYSERR_NOERROR) {
        wave = NULL;
        return 1;
    }
    for (i = 0; i < AUDIO_BUFFERS; i++) {
        memset(&hdr[i], 0, sizeof hdr[i]);
        hdr[i].lpData = (LPSTR)abuf[i];
        hdr[i].dwBufferLength = AUDIO_SAMPLES * 2;
        waveOutPrepareHeader(wave, &hdr[i], sizeof hdr[i]);
    }
    sound_set_volume(cfg_volume);
    return 0;
}

void plat_audio_push(const int16_t *pcm, int frames)
{
    if (!wave) return;
    while (frames > 0) {
        int n = AUDIO_SAMPLES - afill;
        if (n > frames) n = frames;
        memcpy(&abuf[acur][afill], pcm, (size_t)n * 2);
        afill += n;
        pcm += n;
        frames -= n;
        if (afill == AUDIO_SAMPLES) {
            afill = 0;
            if (aqueued < AUDIO_MAX_AHEAD && (hdr[acur].dwFlags & WHDR_INQUEUE) == 0) {
                InterlockedIncrement(&aqueued);
                waveOutWrite(wave, &hdr[acur], sizeof hdr[acur]);
                acur = (acur + 1) % AUDIO_BUFFERS;
            }
            /* else: the device is behind; this buffer is overwritten (dropped) */
        }
    }
}

void plat_audio_close(void)
{
    int i;
    if (!wave) return;
    waveOutReset(wave);
    for (i = 0; i < AUDIO_BUFFERS; i++) waveOutUnprepareHeader(wave, &hdr[i], sizeof hdr[i]);
    waveOutClose(wave);
    wave = NULL;
}

/* ---- video -------------------------------------------------------------- */
static void blit(HDC dc)
{
    RECT r;
    int  cw, ch, s, w, h;
    GetClientRect(hwnd, &r);
    cw = r.right - r.left;
    ch = r.bottom - r.top;
    s = cw / PLAT_VIDEO_W;
    if (ch / PLAT_VIDEO_H < s) s = ch / PLAT_VIDEO_H;
    if (s < 1) s = 1;
    w = PLAT_VIDEO_W * s;
    h = PLAT_VIDEO_H * s;
    StretchDIBits(dc, (cw - w) / 2, (ch - h) / 2, w, h, 0, 0, PLAT_VIDEO_W, PLAT_VIDEO_H,
                  pixels, &bmi, DIB_RGB_COLORS, SRCCOPY);
}

void plat_video_present(const uint8_t *bitmap)
{
    int x, y;
    HDC dc;
    for (y = 0; y < PLAT_VIDEO_H; y++) {
        const uint8_t *line = bitmap + 32 * y;
        uint32_t *out = pixels + PLAT_VIDEO_W * y;
        for (x = 0; x < PLAT_VIDEO_W; x++)
            out[x] = (line[x >> 3] >> (x & 7)) & 1 ? 0x00FFFFFFu : 0x00000000u;
    }
    if (cfg_hidden || !hwnd) return;
    dc = GetDC(hwnd);
    blit(dc);
    ReleaseDC(hwnd, dc);
}

/* ---- input -------------------------------------------------------------- */
static int key(int vk)
{
    return GetForegroundWindow() == hwnd && (GetAsyncKeyState(vk) & 0x8000) != 0;
}

void plat_input_poll(plat_inputs *in)
{
    if (key(VK_LEFT))  paddle -= cfg_key_speed;
    if (key(VK_RIGHT)) paddle += cfg_key_speed;
    if (paddle < 1) paddle = 1;
    if (paddle > 0xFE) paddle = 0xFE;
    in->paddle[0] = in->paddle[1] = (uint8_t)paddle;
    in->coin = (uint8_t)key('5');
    in->start1 = (uint8_t)key('1');
    in->start2 = (uint8_t)key('2');
    in->test = (uint8_t)test_switch;
    in->reset = (uint8_t)reset_request;
    in->quit = (uint8_t)quit_flag;
    reset_request = 0;
}

uint8_t plat_dsw(void) { return cfg_dsw; }

void plat_status_text(const char *s)
{
    if (hwnd) SetWindowTextA(hwnd, s);
}

/* ---- window ------------------------------------------------------------- */
static LRESULT CALLBACK wndproc(HWND h, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_DESTROY:
        quit_flag = 1;
        PostQuitMessage(0);
        return 0;
    case WM_KEYDOWN:
        if (wp == VK_ESCAPE) { quit_flag = 1; DestroyWindow(h); return 0; }
        if (wp == VK_F2 && !(lp & 0x40000000)) test_switch = !test_switch;
        if (wp == VK_F3 && !(lp & 0x40000000)) reset_request = 1;
        return 0;
    case WM_MOUSEMOVE:
        if (cfg_mouse) {
            RECT r;
            int  cw, x = (short)LOWORD(lp);
            GetClientRect(h, &r);
            cw = r.right - r.left;
            if (cw > 0) {
                paddle = x * 256 / cw;
                if (paddle < 1) paddle = 1;
                if (paddle > 0xFE) paddle = 0xFE;
            }
        }
        return 0;
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(h, &ps);
        RECT r;
        GetClientRect(h, &r);
        FillRect(dc, &r, (HBRUSH)GetStockObject(BLACK_BRUSH));
        blit(dc);
        EndPaint(h, &ps);
        return 0;
    }
    case WM_ERASEBKGND:
        return 1;
    }
    return DefWindowProcA(h, msg, wp, lp);
}

int plat_init(void)
{
    WNDCLASSA wc;
    RECT r;
    DWORD style = WS_OVERLAPPEDWINDOW;

    memset(&bmi, 0, sizeof bmi);
    bmi.bmiHeader.biSize = sizeof bmi.bmiHeader;
    bmi.bmiHeader.biWidth = PLAT_VIDEO_W;
    bmi.bmiHeader.biHeight = -PLAT_VIDEO_H;                /* top-down */
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    memset(&wc, 0, sizeof wc);
    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.hCursor = LoadCursorA(NULL, (LPCSTR)IDC_ARROW);
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    wc.lpszClassName = "ClownsPort";
    if (!RegisterClassA(&wc)) return 1;
    r.left = 0; r.top = 0;
    r.right = PLAT_VIDEO_W * cfg_scale;
    r.bottom = PLAT_VIDEO_H * cfg_scale;
    AdjustWindowRect(&r, style, FALSE);
    hwnd = CreateWindowA("ClownsPort", "Clowns", style, CW_USEDEFAULT, CW_USEDEFAULT,
                         r.right - r.left, r.bottom - r.top, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) return 1;
    if (!cfg_hidden) ShowWindow(hwnd, SW_SHOW);
    return 0;
}

void plat_shutdown(void)
{
    if (hwnd) DestroyWindow(hwnd);
    hwnd = NULL;
}

/* ---- settings ------------------------------------------------------------ */
static int ini_int(const char *sec, const char *key_, int def, int lo, int hi, const char *comment)
{
    char buf[64];
    int  v = (int)GetPrivateProfileIntA(sec, key_, def, ini_path);
    if (v < lo) v = lo;
    if (v > hi) v = hi;
    /* write the value that took effect back, with its meaning */
    sprintf(buf, "%d", v);
    WritePrivateProfileStringA(sec, key_, buf, ini_path);
    (void)comment;
    return v;
}

static void load_ini(void)
{
    char *slash;
    int coinage, bonus, resets, extra, jumps;
    GetModuleFileNameA(NULL, ini_path, sizeof ini_path);
    slash = strrchr(ini_path, '\\');
    if (slash) slash[1] = 0;
    strcat(ini_path, "clowns_win.ini");

    coinage = ini_int("dips", "coinage", 0, 0, 3, "0 1C/1P, 1 1C/2P, 2 2C/2P, 3 2C per player");
    bonus   = ini_int("dips", "bonus_game", 0, 0, 3, "0 none, 1 9000, 2 11000, 3 13000");
    resets  = ini_int("dips", "balloon_resets", 0, 0, 1, "0 each row, 1 all rows");
    extra   = ini_int("dips", "extra_jump", 0, 0, 1, "0 at 3000, 1 at 4000");
    jumps   = ini_int("dips", "jumps", 0, 0, 1, "0 = 3 jumps, 1 = 4 jumps");
    cfg_dsw = (uint8_t)(coinage | (bonus << 2) | (resets << 4) | (extra << 5) | (jumps << 6));
    cfg_scale     = ini_int("main", "scale", 3, 1, 6, "window scale");
    cfg_test      = ini_int("main", "self_test", 0, 0, 1, "self-test switch at power-on");
    cfg_mouse     = ini_int("input", "mouse", 1, 0, 1, "mouse X moves the paddle");
    cfg_key_speed = ini_int("input", "key_speed", 4, 1, 32, "paddle counts per frame for Left / Right");
    cfg_volume    = ini_int("sound", "volume", 60, 0, 100, "0-100");
}

static void parse_args(void)
{
    int     argc = 0, i;
    LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return;
    for (i = 1; i < argc; i++) {
        if (!wcscmp(argv[i], L"--test")) cfg_test = 1;
        else if (!wcscmp(argv[i], L"--hidden")) cfg_hidden = 1;
        else if (!wcscmp(argv[i], L"--scale") && i + 1 < argc) {
            cfg_scale = _wtoi(argv[++i]);
            if (cfg_scale < 1) cfg_scale = 1;
            if (cfg_scale > 6) cfg_scale = 6;
        }
        else if (!wcscmp(argv[i], L"--quit-after-frames") && i + 1 < argc) cfg_quit_frames = _wtol(argv[++i]);
    }
    LocalFree(argv);
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    LARGE_INTEGER freq, now;
    double period, next, t, last_status;
    unsigned long frames = 0, status_frames = 0;
    MSG msg;
    (void)inst; (void)prev; (void)cmd; (void)show;

    load_ini();
    parse_args();
    test_switch = cfg_test;
    if (plat_init()) {
        MessageBoxA(NULL, "Cannot create the window.", "Clowns", MB_OK | MB_ICONERROR);
        return 1;
    }
    timeBeginPeriod(1);
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&now);
    period = 1000.0 / CLOWNS_FRAME_HZ;
    next = last_status = now.QuadPart * 1000.0 / freq.QuadPart;
    clowns_app_init();

    while (!quit_flag) {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) quit_flag = 1;
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        if (quit_flag) break;
        QueryPerformanceCounter(&now);
        t = now.QuadPart * 1000.0 / freq.QuadPart;
        if (t < next) {
            Sleep(next - t > 2.0 ? 1 : 0);
            continue;
        }
        clowns_app_frame();
        frames++;
        next += period;
        if (t - next > 100.0) next = t;                    /* fell far behind (window dragged): do not catch up */
        if (t - last_status >= 1000.0) {
            char title[160];
            clowns_app_stats st;
            clowns_app_get_stats(&st);
            sprintf(title, "Clowns - %.1f fps%s%s", (frames - status_frames) * 1000.0 / (t - last_status),
                    test_switch ? " - self-test switch ON" : "",
                    st.loop == 1 ? " - self test" : st.loop == 2 ? " - self test: error shown" :
                    st.loop == 3 ? " - switch test" : "");
            plat_status_text(title);
            status_frames = frames;
            last_status = t;
        }
        if (cfg_quit_frames >= 0 && (long)frames >= cfg_quit_frames) break;
    }
    clowns_app_exit();
    timeEndPeriod(1);
    plat_shutdown();
    return 0;
}
