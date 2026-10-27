#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <math.h>
static HINSTANCE instance;
static wchar_t logPath[MAX_PATH];
static void Log(const wchar_t* msg){FILE*f=nullptr;_wfopen_s(&f,logPath,L"a");if(f){fwprintf(f,L"%llu %s\n",GetTickCount64(),msg);fclose(f);}}
static BOOL CALLBACK FindGame(HWND w,LPARAM param){DWORD pid=0;GetWindowThreadProcessId(w,&pid);if(pid!=GetCurrentProcessId()||!IsWindowVisible(w))return TRUE;wchar_t title[256];GetWindowTextW(w,title,256);RECT r;GetClientRect(w,&r);if(wcsstr(title,L"ON THE BEACH v")&&r.right>=960&&r.bottom>=540){*(HWND*)param=w;return FALSE;}return TRUE;}
// Recognize the title menu from its distinctive portrait and right-hand menu.
// Samples remain in memory; no screen image is saved or transmitted.
static bool IsTitleMenu(HWND game){
 if(GetForegroundWindow()!=game)return false;
 RECT r;GetClientRect(game,&r);POINT p={0,0};ClientToScreen(game,&p);int width=r.right,height=r.bottom;
 if(width<960||height<540)return false;
 HDC screen=GetDC(NULL),mem=CreateCompatibleDC(screen);BITMAPINFO bi={};bi.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);bi.bmiHeader.biWidth=192;bi.bmiHeader.biHeight=-108;bi.bmiHeader.biPlanes=1;bi.bmiHeader.biBitCount=32;bi.bmiHeader.biCompression=BI_RGB;void*bits=nullptr;
 HBITMAP bitmap=CreateDIBSection(screen,&bi,DIB_RGB_COLORS,&bits,NULL,0);if(!bitmap){DeleteDC(mem);ReleaseDC(NULL,screen);return false;}HGDIOBJ old=SelectObject(mem,bitmap);SetStretchBltMode(mem,COLORONCOLOR);BOOL copied=StretchBlt(mem,0,0,192,108,screen,p.x,p.y,width,height,SRCCOPY);
 int light=0,red=0,dark=0,menu=0;auto pix=(DWORD*)bits;
 if(copied){
  for(int y=8;y<25;y++)for(int x=2;x<22;x++){DWORD v=pix[y*192+x];int b=v&255,g=(v>>8)&255,rr=(v>>16)&255;if(rr>160&&g>155&&b>150)light++;}
  for(int y=15;y<65;y++)for(int x=115;x<136;x++){DWORD v=pix[y*192+x];int b=v&255,g=(v>>8)&255,rr=(v>>16)&255;if(rr>75&&rr>g*1.5&&rr>b*1.3)red++;}
  for(int y=15;y<65;y++)for(int x=175;x<190;x++){DWORD v=pix[y*192+x];if(((v>>16)&255)<90&&((v>>8)&255)<70&&(v&255)<70)dark++;}
  for(int y=70;y<102;y++)for(int x=132;x<156;x++){DWORD v=pix[y*192+x];int b=v&255,g=(v>>8)&255,rr=(v>>16)&255;if(rr>85&&g>85&&b>85&&abs(rr-g)<35&&abs(g-b)<35)menu++;}
 }
 SelectObject(mem,old);DeleteObject(bitmap);DeleteDC(mem);ReleaseDC(NULL,screen);
 return copied&&light>220&&red>350&&dark>300&&menu>22;
}
static LRESULT CALLBACK OverlayProc(HWND w,UINT m,WPARAM a,LPARAM b){
 if(m==WM_NCHITTEST)return HTTRANSPARENT;
 if(m==WM_PAINT){PAINTSTRUCT ps;HDC dc=BeginPaint(w,&ps);RECT r;GetClientRect(w,&r);FillRect(dc,&r,(HBRUSH)GetStockObject(BLACK_BRUSH));SetBkMode(dc,TRANSPARENT);SetTextColor(dc,RGB(235,245,255));HFONT f=CreateFontW(-32,0,0,0,FW_MEDIUM,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,L"Segoe UI");HGDIOBJ old=SelectObject(dc,f);DrawTextW(dc,L"gggg-unit",-1,&r,DT_CENTER|DT_VCENTER|DT_SINGLELINE);SelectObject(dc,old);DeleteObject(f);EndPaint(w,&ps);return 0;}
 return DefWindowProcW(w,m,a,b);
}
static DWORD WINAPI Worker(void*){
 Log(L"started");HWND game=nullptr;int stable=0;ULONGLONG deadline=GetTickCount64()+300000;
 while(GetTickCount64()<deadline){game=nullptr;EnumWindows(FindGame,(LPARAM)&game);if(game&&IsTitleMenu(game)){if(++stable>=3)break;}else stable=0;Sleep(200);}
 if(stable<3){Log(L"menu timeout");return 0;}Log(L"menu detected");
 WNDCLASSW wc={};wc.lpfnWndProc=OverlayProc;wc.hInstance=instance;wc.lpszClassName=L"DS2IntroNotice";wc.hbrBackground=(HBRUSH)GetStockObject(BLACK_BRUSH);RegisterClassW(&wc);
 RECT r;GetClientRect(game,&r);POINT p={0,0};ClientToScreen(game,&p);int width=360,height=58;int x=p.x+(r.right-width)/2,y=p.y+(int)(r.bottom*.10);
 HWND overlay=CreateWindowExW(WS_EX_LAYERED|WS_EX_TRANSPARENT|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,wc.lpszClassName,L"",WS_POPUP,x,y,width,height,game,NULL,instance,NULL);
 if(!overlay){Log(L"window failed");return 0;}SetLayeredWindowAttributes(overlay,RGB(0,0,0),255,LWA_COLORKEY|LWA_ALPHA);SetWindowPos(overlay,HWND_TOPMOST,x,y,width,height,SWP_NOACTIVATE|SWP_SHOWWINDOW);UpdateWindow(overlay);Log(L"shown");
 ULONGLONG started=GetTickCount64();MSG msg;
 while(GetTickCount64()-started<3000&&IsWindow(game)){
  while(PeekMessageW(&msg,NULL,0,0,PM_REMOVE)){TranslateMessage(&msg);DispatchMessageW(&msg);}
  ULONGLONG elapsed=GetTickCount64()-started;BYTE alpha=elapsed<2700?255:(BYTE)((3000-elapsed)*255/300);SetLayeredWindowAttributes(overlay,RGB(0,0,0),alpha,LWA_COLORKEY|LWA_ALPHA);
  if(GetForegroundWindow()!=game)ShowWindow(overlay,SW_HIDE);else ShowWindow(overlay,SW_SHOWNOACTIVATE);Sleep(15);
 }
 DestroyWindow(overlay);UnregisterClassW(wc.lpszClassName,instance);Log(L"hidden; done");return 0;
}
extern "C" __declspec(dllexport) const char* DS2GetKey(){return "PlayCeviri_Secure_Key_2026_V19!!";}
extern "C" __declspec(dllexport) const char* DS2Prepare(){
 static volatile LONG once=0;
 if(InterlockedCompareExchange(&once,1,0)==0){
  wchar_t exe[MAX_PATH];GetModuleFileNameW(NULL,exe,MAX_PATH);wchar_t*p=wcsrchr(exe,L'\\');if(p){*p=0;SetCurrentDirectoryW(exe);}
  HANDLE t=CreateThread(NULL,0,Worker,NULL,0,NULL);if(t)CloseHandle(t);
 }
 return DS2GetKey();
}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID){
 if(reason==DLL_PROCESS_ATTACH){instance=h;DisableThreadLibraryCalls(h);GetModuleFileNameW(h,logPath,MAX_PATH);wchar_t*p=wcsrchr(logPath,L'\\');if(p)wcscpy_s(p+1,MAX_PATH-(p+1-logPath),L"DS2_Intro.log");}
 return TRUE;
}
