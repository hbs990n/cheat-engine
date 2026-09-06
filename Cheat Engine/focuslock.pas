unit focuslock;
// Experimental: global "don't steal focus" mode.
// F12 toggles it. When enabled, every CE top-level window gets
// WS_EX_NOACTIVATE so it can never become (or steal) the foreground
// window - no matter how it is shown. CE can be viewed but not
// keyboard-activated while the mode is on. Press F12 again to unlock.
//
// The F12 hotkey is registered on a hidden WinAPI-only message window
// (no LCL Application.OnMessage dependency), so it works globally and is
// independent of the LCL message routing.

{$MODE Delphi}

interface

uses
  Classes, SysUtils, Controls, Forms;

procedure InitFocusLock;
procedure ShutdownFocusLock;
function IsFocusLockOn: boolean;

implementation

uses
  Windows;

const
  FocusLockHotkeyID = $B0C0;
  FocusLockHotkey = $7B;                    //VK_F12
  FocusLockModNoRepeat = $4000;             //MOD_NOREPEAT
  FocusLockMinToggleInterval = 250;         //ms debounce
  FocusLockWindowClassName: PChar = 'CEFocusLockWindow';
  cWS_EX_NOACTIVATE = $08000000;
  cGWL_EXSTYLE = -20;

type
  TFocusLockHelper = class
  public
    procedure FormAdded(Form: TCustomForm);
  end;

var
  NoFocusSteal: boolean = false;
  Helper: TFocusLockHelper;
  FocusLockWindow: HWND = 0;
  HotkeyRegistered: boolean = false;
  WindowClassRegistered: boolean = false;
  LastToggleTick: DWORD = 0;

procedure ApplyNoActivate(Form: TCustomForm);
var ex: longint;
begin
  if (Form=nil) or (not Form.HandleAllocated) or (csDestroying in Form.ComponentState) then exit;

  ex:=GetWindowLong(Form.Handle, cGWL_EXSTYLE);
  if (ex and cWS_EX_NOACTIVATE)=0 then
    SetWindowLong(Form.Handle, cGWL_EXSTYLE, ex or cWS_EX_NOACTIVATE);
end;

procedure ClearNoActivate(Form: TCustomForm);
var ex: longint;
begin
  if (Form=nil) or (not Form.HandleAllocated) or (csDestroying in Form.ComponentState) then exit;

  ex:=GetWindowLong(Form.Handle, cGWL_EXSTYLE);
  if (ex and cWS_EX_NOACTIVATE)<>0 then
    SetWindowLong(Form.Handle, cGWL_EXSTYLE, ex and (not cWS_EX_NOACTIVATE));
end;

procedure ApplyToAllForms;
var i: integer;
begin
  if Screen=nil then exit;

  for i:=0 to Screen.FormCount-1 do
    ApplyNoActivate(Screen.Forms[i]);
end;

procedure ClearFromAllForms;
var i: integer;
begin
  if Screen=nil then exit;

  for i:=0 to Screen.FormCount-1 do
    ClearNoActivate(Screen.Forms[i]);
end;

procedure SetNoFocusSteal(Enable: boolean);
begin
  if Enable=NoFocusSteal then exit;
  NoFocusSteal:=Enable;

  if Enable then
    ApplyToAllForms
  else
    ClearFromAllForms;
end;

procedure TFocusLockHelper.FormAdded(Form: TCustomForm);
begin
  if NoFocusSteal then
    ApplyNoActivate(Form);
end;

function IsFocusLockOn: boolean;
begin
  result:=NoFocusSteal;
end;

function FocusLockWndProc(h: HWND; msg: UINT; w: WPARAM; l: LPARAM): LRESULT; stdcall;
begin
  if (msg=WM_HOTKEY) and (w=FocusLockHotkeyID) then
  begin
    if (GetTickCount-LastToggleTick)>=FocusLockMinToggleInterval then
    begin
      LastToggleTick:=GetTickCount;
      SetNoFocusSteal(not NoFocusSteal);
    end;

    result:=0;
    exit;
  end;

  result:=DefWindowProc(h, msg, w, l);
end;

procedure InitFocusLock;
var wc: TWNDCLASS;
begin
  if FocusLockWindow<>0 then exit;

  Helper:=TFocusLockHelper.Create;
  Screen.AddHandlerFormAdded(Helper.FormAdded);

  if not WindowClassRegistered then
  begin
    FillChar(wc, sizeof(wc), 0);
    wc.lpfnWndProc:=@FocusLockWndProc;
    wc.hInstance:=GetModuleHandle(nil);
    wc.lpszClassName:=FocusLockWindowClassName;

    if RegisterClass(wc)<>0 then
      WindowClassRegistered:=true
    else
    if GetLastError()=ERROR_CLASS_ALREADY_EXISTS then
      WindowClassRegistered:=true; //already present (registered by an earlier init); fine
  end;

  FocusLockWindow:=CreateWindowEx(0, FocusLockWindowClassName, 'CEFocusLock',
                                  0, 0, 0, 0, 0, 0, 0, GetModuleHandle(nil), nil);

  if FocusLockWindow<>0 then
    HotkeyRegistered:=RegisterHotKey(FocusLockWindow, FocusLockHotkeyID, FocusLockModNoRepeat, FocusLockHotkey);
end;

procedure ShutdownFocusLock;
begin
  if FocusLockWindow<>0 then
  begin
    if HotkeyRegistered then
      UnregisterHotKey(FocusLockWindow, FocusLockHotkeyID);

    HotkeyRegistered:=false;
    DestroyWindow(FocusLockWindow);
    FocusLockWindow:=0;
  end;

  if WindowClassRegistered then
  begin
    UnregisterClass(FocusLockWindowClassName, GetModuleHandle(nil));
    WindowClassRegistered:=false;
  end;

  if NoFocusSteal then
    SetNoFocusSteal(false);

  if Helper<>nil then
  begin
    Screen.RemoveHandlerFormAdded(Helper.FormAdded);
    FreeAndNil(Helper);
  end;
end;

initialization

finalization
  ShutdownFocusLock;

end.