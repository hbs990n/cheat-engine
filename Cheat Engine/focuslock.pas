unit focuslock;
// Experimental: global "don't steal focus" mode.
// F12 toggles it. When enabled, every CE top-level window gets
// WS_EX_NOACTIVATE so it can never become (or steal) the foreground
// window - no matter how it is shown. CE can be viewed but not
// keyboard-activated while the mode is on. Press F12 again to unlock.

{$MODE Delphi}

interface

uses
  Classes, SysUtils, Controls, Forms;

procedure InitFocusLock;
procedure ShutdownFocusLock;
function IsFocusLockOn: boolean;

implementation

uses
  Windows, LCLType;

const
  FocusLockHotkeyID = $B0C0;
  FocusLockHotkey = $7B;                    //VK_F12
  FocusLockModNoRepeat = $4000;             //MOD_NOREPEAT
  FocusLockMinToggleInterval = 250;         //ms debounce
  cWS_EX_NOACTIVATE = $08000000;
  cGWL_EXSTYLE = -20;
  cWM_HOTKEY = $0312;

type
  TFocusLockHelper = class
  public
    procedure FormAdded(Form: TCustomForm);
  end;

var
  NoFocusSteal: boolean = false;
  Helper: TFocusLockHelper;
  HotkeyRegistered: boolean = false;
  MessageHookInstalled: boolean = false;
  OldOnMessage: TMessageEvent;
  LastToggleTick: QWord = 0;

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
  for i:=0 to Screen.FormCount-1 do
    ApplyNoActivate(Screen.Forms[i]);
end;

procedure ClearFromAllForms;
var i: integer;
begin
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

procedure FocusLockMessageHook(var Message: TLMessage; var Handled: Boolean);
begin
  if (Message.Msg=cWM_HOTKEY) and (Message.wParam=FocusLockHotkeyID) then
  begin
    if GetTickCount64-LastToggleTick>=FocusLockMinToggleInterval then
    begin
      LastToggleTick:=GetTickCount64;
      SetNoFocusSteal(not NoFocusSteal);
    end;

    Handled:=true;
  end
  else
  if MessageHookInstalled and Assigned(OldOnMessage) then
    OldOnMessage(Message, Handled);
end;

procedure InitFocusLock;
begin
  if HotkeyRegistered then exit;

  Helper:=TFocusLockHelper.Create;
  Screen.AddHandlerFormAdded(Helper.FormAdded);

  HotkeyRegistered:=RegisterHotKey(Application.Handle, FocusLockHotkeyID, FocusLockModNoRepeat, FocusLockHotkey);

  OldOnMessage:=Application.OnMessage;
  Application.OnMessage:=@FocusLockMessageHook;
  MessageHookInstalled:=true;
end;

procedure ShutdownFocusLock;
begin
  if MessageHookInstalled then
  begin
    Application.OnMessage:=OldOnMessage;
    MessageHookInstalled:=false;
  end;

  if HotkeyRegistered then
  begin
    UnregisterHotKey(Application.Handle, FocusLockHotkeyID);
    HotkeyRegistered:=false;
  end;

  if NoFocusSteal then
    SetNoFocusSteal(false);

  if Helper<>nil then
  begin
    Screen.RemoveHandlerFormAdded(Helper.FormAdded);
    FreeAndNil(Helper);
  end;
end;

function IsFocusLockOn: boolean;
begin
  result:=NoFocusSteal;
end;

initialization

finalization
  ShutdownFocusLock;

end.