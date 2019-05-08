.386
.model flat,stdcall
option casemap:none

WinMain proto :DWORD,:DWORD,:DWORD,:DWORD

include \masm32\include\windows.inc
include \masm32\include\user32.inc
include \masm32\include\gdi32.inc
include \masm32\include\kernel32.inc
includelib \masm32\lib\user32.lib
includelib \masm32\lib\kernel32.lib
includelib \masm32\lib\gdi32.lib

; -----------------------------------
; INPUT red, green & blue BYTE values
; OUTPUT DWORD COLORREF value in eax
; -----------------------------------
  RGB MACRO red, green, blue
    xor eax, eax
    mov ah, blue    ; blue
    mov al, green   ; green
    rol eax, 8
    mov al, red     ; red
  ENDM
  
WinMain proto :DWORD,:DWORD,:DWORD,:DWORD

Animate	equ	6060h

.data
ClassName	BYTE	"MainWinClass",0
AppName		BYTE	"Main Window",0
tempDC		DWORD	0				;Temp DC (only used to create compatibles for drawing
backDC		DWORD	0				;DC for background image (to be blitted to main screen)
imageDC		DWORD	0				;DC to hold original image (background will be rotated and sized)
ourArea		RECT	<>

.data?
hInstance		HINSTANCE	?
hDesktop		DWORD		?
CommandLine		LPSTR		?
oldBackBmp		DWORD		?		;To restore displaced bmp object from backDC
oldImgBmp		DWORD		?		;To restore displaced bmp object from imageDC
DesktopX		DWORD		?
DesktopY		DWORD		?
LocationX		DWORD		?
LocationY		DWORD		?
SourceX		DWORD		?
SourceY		DWORD		?
FrameSizeX        DWORD       ?
FrameSizeY        DWORD       ?

ifndef CStr

	CStr	macro	y:req
		local	sym,xxx
	xxx	textequ	@CurSeg
		.const
		ifidni	<y>,<"">
			sym	db	0
		else
			sym	db	y,0
		endif
		ifidni	xxx,<_TEXT>
			.code
		else
			.data
		endif
		exitm	<offset sym>
	endm

endif

.code

; ---------------------------------------------------------------------------

start:
	invoke GetModuleHandle, NULL
	mov    hInstance,eax
	
	invoke GetCommandLine
	mov    CommandLine,eax

      mov    FrameSizeX,48
      mov    FrameSizeY,69
      	
	invoke WinMain, hInstance,NULL,CommandLine, SW_SHOWDEFAULT
	invoke ExitProcess,eax

WinMain proc hInst:HINSTANCE,hPrevInst:HINSTANCE,CmdLine:LPSTR,CmdShow:DWORD
	LOCAL wc:WNDCLASSEX
	LOCAL msg:MSG
	LOCAL hwnd:HWND
	
	mov   wc.cbSize,SIZEOF WNDCLASSEX
	mov   wc.style, CS_HREDRAW or CS_VREDRAW
	mov   wc.lpfnWndProc, OFFSET WndProc
	mov   wc.cbClsExtra,NULL
	mov   wc.cbWndExtra,NULL
	push  hInstance
	pop   wc.hInstance
	mov   wc.hbrBackground,COLOR_BTNFACE+1
	mov   wc.lpszMenuName,NULL
	mov   wc.lpszClassName,OFFSET ClassName
	
	invoke LoadIcon,NULL,IDI_APPLICATION
	mov   wc.hIcon,eax
	mov   wc.hIconSm,eax
	
	invoke LoadCursor,NULL,IDC_ARROW
	mov   wc.hCursor,eax
	
	invoke RegisterClassEx, addr wc
	INVOKE CreateWindowEx,WS_EX_LAYERED,ADDR ClassName,ADDR AppName,\
           WS_POPUP or WS_VISIBLE or WS_SYSMENU,CW_USEDEFAULT,\
           CW_USEDEFAULT,FrameSizeX,FrameSizeY,NULL,NULL,\
           hInst,NULL
	mov   hwnd,eax
	
	invoke ShowWindow, hwnd,SW_SHOWNORMAL
	invoke UpdateWindow, hwnd
	
	.WHILE TRUE
		invoke GetMessage, ADDR msg,NULL,0,0
		.BREAK .IF (!eax)
		invoke TranslateMessage, ADDR msg
		invoke DispatchMessage, ADDR msg
	.ENDW
	
	mov     eax,msg.wParam
	ret
WinMain endp

WndProc proc hWnd:HWND, uMsg:UINT, wParam:WPARAM, lParam:LPARAM

LOCAL	ps:PAINTSTRUCT
		
	.IF uMsg==WM_TIMER
		.if	wParam == Animate
			invoke BitBlt,backDC,0,0,FrameSizeX,FrameSizeY,imageDC,SourceX,SourceY,SRCCOPY
			
			;We have to adjust the source coordinates for blitting
			;the sprite sheet image to the back buffer DC (then bring it forward during WM_PAINT)
			
			mov	eax,SourceX
			add	eax,FrameSizeX
			mov	SourceX,eax
			.if	eax > 400
				mov	eax,1					
				mov	SourceX,eax
				mov	eax,SourceY
				add	eax,102
			.endif
			
			invoke	MoveWindow,hWnd,LocationX,LocationY,FrameSizeX,FrameSizeY,FALSE
			mov		eax,LocationX
			add		eax,6
			mov		LocationX,eax
			mov		ecx,DesktopX
			.if		eax >= ecx
				mov	eax,0
				mov	LocationX,eax
			.endif
			invoke InvalidateRect,hWnd,0,FALSE
		.endif
		
	.ELSEIF uMsg==WM_PAINT
		invoke BeginPaint,hWnd,ADDR ps
			mov edx,ps.rcPaint.right
			sub edx,ps.rcPaint.left
			mov ecx,ps.rcPaint.bottom
			sub ecx,ps.rcPaint.top
			invoke BitBlt,ps.hdc,ps.rcPaint.left,ps.rcPaint.top,edx,ecx,backDC,ps.rcPaint.left,ps.rcPaint.top,SRCCOPY
		invoke EndPaint,hWnd,ADDR ps
	.ELSEIF uMsg==WM_LBUTTONDOWN
		invoke SendMessage, hWnd, WM_NCLBUTTONDOWN, HTCAPTION, 0       
	.ELSEIF uMsg==WM_DESTROY
		invoke	SelectObject,backDC,oldBackBmp
		invoke	DeleteObject,eax
		invoke	DeleteDC,backDC
		invoke	SelectObject,imageDC,oldImgBmp
		invoke	DeleteObject,eax
		invoke	DeleteDC,imageDC
		invoke	KillTimer,hWnd,Animate
		invoke PostQuitMessage,NULL
	.ELSEIF uMsg==WM_CREATE
		mov	SourceX,1
		mov	SourceY,1
		RGB	80,128,208
		invoke SetLayeredWindowAttributes,hWnd, eax, 0, LWA_COLORKEY
		invoke	GetClientRect,hWnd,ADDR ourArea
		RGB	80,128,208
		invoke	FillRect,hWnd,ADDR ourArea,eax

		;2 backbuffer DC's
		;one for drawing on and one for keeping original image

		invoke	GetSystemMetrics,SM_CXSCREEN
		mov DesktopX,eax
		invoke	GetSystemMetrics,SM_CYSCREEN
		mov DesktopY,eax
		
		mov	LocationX,0
		mov	eax,DesktopY
		sub	eax,110					;run along the top of the system tray
		mov	LocationY,eax
		
		invoke	GetDesktopWindow
		mov		hDesktop,eax
		invoke	GetDC,hDesktop
		mov		tempDC,eax
		
		invoke	CreateCompatibleDC,tempDC
		mov		backDC,eax
		
		invoke	GetClientRect,hWnd,ADDR ourArea
		invoke	CreateCompatibleBitmap,tempDC,ourArea.right,ourArea.bottom
		invoke	SelectObject,backDC,eax
		mov		oldBackBmp,eax
	
		invoke	CreateCompatibleDC,tempDC
		mov		imageDC,eax
		
		invoke	LoadImage,  NULL,CStr("Hulk.bmp"),IMAGE_BITMAP,0,0,LR_LOADFROMFILE		
		
		.if !eax
			invoke MessageBeep,0FFFFFFFFh
			invoke ExitProcess,0
		.endif
		invoke	SelectObject,imageDC,eax
		mov	oldImgBmp,eax

		invoke ReleaseDC,hDesktop,tempDC

		invoke BitBlt,backDC,ourArea.left,ourArea.top,FrameSizeX,FrameSizeY,imageDC,SourceX,SourceY,SRCCOPY

		;timer to change the animation
		; 22 = 45 times per second
		invoke SetTimer,hWnd,Animate,80,0
	.ELSE
		invoke DefWindowProc,hWnd,uMsg,wParam,lParam		
		ret
	.ENDIF
	
	xor eax,eax
	ret
WndProc endp

end start
