using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Automation;
namespace AC8Settings {
 public static class SelfTest {
  static IEnumerable<DependencyObject> Children(DependencyObject root){
   yield return root;
   for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++)foreach(var child in Children(VisualTreeHelper.GetChild(root,i)))yield return child;
  }
  public static int UI(string[] args){
   string root=Program.Arg(args,"--package",null),report=Program.Arg(args,"--report",null);
   try{
    var app=new Application();var ui=new SettingsWindow(root,true);
    ui.Window.Left=-12000;ui.Window.Top=-12000;ui.Window.WindowStartupLocation=WindowStartupLocation.Manual;ui.Window.ShowInTaskbar=false;ui.Window.ShowActivated=false;ui.Window.Show();
    ui.ShowPage(9);ui.Window.UpdateLayout();
    var guide=Children(ui.Window).OfType<TextBox>().Single(x=>AutomationProperties.GetName(x)=="MSL 引导数值");
    Check(guide.Text==new ConfigStore(root).State.Values["guidance_MSL"].ToString("0.000",System.Globalization.CultureInfo.InvariantCulture),"Guidance page did not load saved value.");
    string guidanceBefore=File.Exists(Path.Combine(root,"MissileGuidance.ini"))?File.ReadAllText(Path.Combine(root,"MissileGuidance.ini")):null;
    guide.Text="1.1";((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check((File.Exists(Path.Combine(root,"MissileGuidance.ini"))?File.ReadAllText(Path.Combine(root,"MissileGuidance.ini")):null)==guidanceBefore,"Invalid guidance UI value saved.");
    guide.Text="0.5";((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.Values["guidance_MSL"]==.5,"Guidance UI value not saved.");
    ui.Window.UpdateLayout();
    Children(ui.Window).OfType<Button>().Single(x=>AutomationProperties.GetName(x)=="QAAM 恢复原版值").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    ((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.Values["guidance_QAAM"]==.4,"Stock guidance reset failed.");
    ui.Window.UpdateLayout();
    Children(ui.Window).OfType<Expander>().Single().IsExpanded=true;ui.Window.UpdateLayout();
    guide=Children(ui.Window).OfType<TextBox>().Single(x=>AutomationProperties.GetName(x)=="EASY 引导数值");guide.Text="0.55";
    ((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.Values["guidance_EASY"]==.55,"Advanced guidance UI did not save.");
    ((Button)ui.Window.FindName("PageDefaults")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    ((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.Values["guidance_MSL"]==1&&new ConfigStore(root).State.Values["guidance_QAAM"]==1,"Guidance defaults failed.");
    ui.ShowPage(0);ui.Window.UpdateLayout();
    CheckTextFits(Children(ui.Window).OfType<TextBox>().Single(x=>AutomationProperties.GetName(x)=="鼠标灵敏度数值"));
    CheckTextFits(Children(ui.Window).OfType<TextBox>().Single(x=>AutomationProperties.GetName(x)=="自由观察放大数值"));
    var frameToggle=Children(ui.Window).OfType<CheckBox>().Single(x=>AutomationProperties.GetName(x)=="DLSS 帧生成");
    string framePath=Path.Combine(root,"FrameGeneration.ini");
    string frameBefore=File.ReadAllText(framePath);bool frameInitial=new ConfigStore(root).State.FrameGenerationEnabled;
    Check(frameToggle.IsChecked==frameInitial,"Frame generation UI did not load saved setting.");
    frameToggle.IsChecked=!frameInitial;
    Check(File.ReadAllText(framePath)==frameBefore,"Frame generation wrote before Save.");
    ((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.FrameGenerationEnabled!=frameInitial,"Frame generation UI did not save.");
    ui.ShowPage(2);ui.ShowPage(0);ui.Window.UpdateLayout();
    frameToggle=Children(ui.Window).OfType<CheckBox>().Single(x=>AutomationProperties.GetName(x)=="DLSS 帧生成");
    Check(frameToggle.IsChecked==!frameInitial,"Frame generation UI state lost after navigation.");
    frameToggle.IsChecked=false;
    ((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(!new ConfigStore(root).State.FrameGenerationEnabled,"Frame generation did not disable.");
    Check(!Children(ui.Window).OfType<TextBlock>().Any(x=>x.Text=="灵敏度快捷值"),"Sensitivity presets remain.");
    var saveButton=(Button)ui.Window.FindName("Save");var startButton=(Button)ui.Window.FindName("StartGame");
    var steamChoice=(CheckBox)ui.Window.FindName("SteamLaunch");
    Check((string)startButton.Tag=="primary"&&saveButton.Tag==null,"Action hierarchy is wrong.");
    Check(saveButton.TranslatePoint(new Point(),ui.Window).X<steamChoice.TranslatePoint(new Point(),ui.Window).X&&steamChoice.TranslatePoint(new Point(),ui.Window).X<startButton.TranslatePoint(new Point(),ui.Window).X,"Footer action order is wrong.");
    Check(ui.Window.FindName("Theme")==null,"Theme toggle remains.");
    var stateChoice=Children(ui.Window).OfType<ComboBox>().Single();stateChoice.IsDropDownOpen=true;
    ui.Window.Dispatcher.Invoke(new Action(()=>{}),System.Windows.Threading.DispatcherPriority.ApplicationIdle);ui.Window.UpdateLayout();
    var selectedItem=(ComboBoxItem)stateChoice.ItemContainerGenerator.ContainerFromIndex(stateChoice.SelectedIndex);
    Check(((SolidColorBrush)selectedItem.Foreground).Color==Colors.White,"Selected dropdown text lacks contrast.");
    var popup=(System.Windows.Controls.Primitives.Popup)stateChoice.Template.FindName("PART_Popup",stateChoice);
    var popupContent=(FrameworkElement)popup.Child;popupContent.UpdateLayout();
    var popupBitmap=new System.Windows.Media.Imaging.RenderTargetBitmap((int)Math.Ceiling(popupContent.ActualWidth*1.5),(int)Math.Ceiling(popupContent.ActualHeight*1.5),144,144,PixelFormats.Pbgra32);popupBitmap.Render(popupContent);
    var popupEncoder=new System.Windows.Media.Imaging.PngBitmapEncoder();popupEncoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(popupBitmap));
    using(var output=File.Create(Path.Combine(Path.GetDirectoryName(report),"dropdown-state.png")))popupEncoder.Save(output);
    stateChoice.IsDropDownOpen=false;
    var focusTrigger=startButton.Template.Triggers.OfType<Trigger>().Single(x=>x.Property==UIElement.IsKeyboardFocusedProperty);
    Check(focusTrigger.Setters.OfType<Setter>().Any(x=>x.TargetName=="Surface"&&x.Property==Border.BorderBrushProperty&&((SolidColorBrush)x.Value).Color==Color.FromRgb(0x14,0x2F,0x3C)),"Primary action lacks a contrasting keyboard focus border.");
    ui.ShowPage(8);ui.Window.UpdateLayout();
    Check(Children((DependencyObject)ui.Window.FindName("PageBody")).OfType<Button>().Count()==1,"Help includes non-install actions.");
    ui.ShowPage(0);ui.Window.UpdateLayout();
    var input=Children(ui.Window).OfType<TextBox>().Single(x=>AutomationProperties.GetName(x)=="鼠标灵敏度数值");
    string before=File.ReadAllText(Path.Combine(root,"MouseAim-Settings.ini"));
    input.Text="10";((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(File.ReadAllText(Path.Combine(root,"MouseAim-Settings.ini"))==before,"Invalid UI input wrote configuration.");
    input.Text="0.123";((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.Values["sensitivity"]==.123,"UI numeric input did not save.");
    ui.ShowPage(2);ui.Window.UpdateLayout();
    input=Children(ui.Window).OfType<TextBox>().Single(x=>AutomationProperties.GetName(x)=="准星颜色十六进制值");
    input.Text="#FFBD4A";((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.Color=="#FFBD4A","UI color did not save.");
    ui.ShowPage(1);ui.Window.UpdateLayout();
    var modes=Children(ui.Window).OfType<ComboBox>().Single(x=>AutomationProperties.GetName(x)=="机外相机模式");
    modes.SelectedIndex=1;((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.Values["camera_mode"]==1,"Camera selection not saved.");
    ui.Window.UpdateLayout();
    var fov=Children(ui.Window).OfType<TextBox>().Single(x=>AutomationProperties.GetName(x)=="驾驶舱 FOV数值");
    string fovBefore=File.ReadAllText(Path.Combine(root,"FOV.ini"));
    fov.Text="20";((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(File.ReadAllText(Path.Combine(root,"FOV.ini"))==fovBefore,"Invalid FOV UI input wrote settings.");
    fov.Text="120";((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.Values["fov_cockpit"]==120,"FOV UI input not saved.");
    ui.Window.UpdateLayout();
    CheckTextFits(Children(ui.Window).OfType<TextBox>().Single(x=>AutomationProperties.GetName(x)=="驾驶舱 FOV数值"));
    var fpResponse=Children(ui.Window).OfType<TextBox>().Single(x=>AutomationProperties.GetName(x)=="驾驶舱响应速度数值");
    string fpBefore=File.ReadAllText(Path.Combine(root,"MouseAim-Settings.ini"));
    fpResponse.Text="25";((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(File.ReadAllText(Path.Combine(root,"MouseAim-Settings.ini"))==fpBefore,"Invalid first-person response saved.");
    fpResponse.Text="4.5";((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.Values["first_person_response"]==4.5,"First-person response not saved.");
    var fpToggle=Children(ui.Window).OfType<CheckBox>().Single(x=>AutomationProperties.GetName(x)=="驾驶舱跟随圆圈");
    fpToggle.IsChecked=false;((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.Values["first_person_follow"]==0,"First-person follow toggle not saved.");
    ((Button)ui.Window.FindName("PageDefaults")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    ((Button)ui.Window.FindName("Save")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Check(new ConfigStore(root).State.Values["camera_mode"]==1,"Page defaults did not restore original external follow.");
    Check(new ConfigStore(root).State.Values["fov_cockpit"]==0,"FOV page defaults did not restore original FOV.");
    Check(new ConfigStore(root).State.Values["first_person_follow"]==1&&new ConfigStore(root).State.Values["first_person_response"]==6,"First-person defaults not restored.");
    Check(new ConfigStore(root).State.Values["guidance_MSL"]==1,"Detached guidance input replayed a stale value after changing pages.");
    Check(((TextBlock)ui.Window.FindName("ModName")).Text=="FPMCI","MOD name is missing.");
    Check(ui.Window.Title.Contains("FPMCI"),"Window title did not adopt FPMCI.");
    foreach(int pageIndex in Enumerable.Range(0,10)){
     ui.ShowPage(pageIndex);ui.Window.UpdateLayout();
     foreach(var numeric in Children(ui.Window).OfType<TextBox>().Where(x=>AutomationProperties.GetName(x).EndsWith("数值")))CheckTextFits(numeric);
    }
    ui.Window.Width=980;ui.Window.Height=720;ui.ShowPage(0);ui.Window.UpdateLayout();
    foreach(var numeric in Children(ui.Window).OfType<TextBox>().Where(x=>AutomationProperties.GetName(x).EndsWith("数值")))CheckTextFits(numeric);
    Check(startButton.TranslatePoint(new Point(startButton.ActualWidth,startButton.ActualHeight),ui.Window).X<=ui.Window.ActualWidth,"Start action overflows narrow window.");
    ui.Window.Close();
    File.WriteAllText(report,"PASS\r\nGuidance UI: saved values, invalid input, stock/default resets and advanced difficulty save passed.\r\nUI numeric validation, numeric/color/FOV save, camera selection, first-person toggle/response and page defaults.",Encoding.UTF8);
    return 0;
   }catch(Exception ex){File.WriteAllText(report,"FAIL\r\n"+ex,Encoding.UTF8);return 1;}
  }
  static void Check(bool condition,string message){if(!condition)throw new Exception(message);}
  static void CheckTextFits(TextBox input){
   input.UpdateLayout();
   Rect first=input.GetRectFromCharacterIndex(0),last=input.GetRectFromCharacterIndex(input.Text.Length-1,true);
   Check(!first.IsEmpty&&!last.IsEmpty&&first.Left>=0&&last.Right<=input.ActualWidth-input.BorderThickness.Right,"Numeric text clipped: "+AutomationProperties.GetName(input));
  }
  static void Reject(Action action,string message){bool rejected=false;try{action();}catch{rejected=true;}Check(rejected,message);}
  public static int Run(string[] args){
   string source=Program.Arg(args,"--package",null),fixture=Program.Arg(args,"--fixture",null),report=Program.Arg(args,"--report",null);
   if(source==null||fixture==null||report==null)throw new ArgumentException("Self-test needs --package, --fixture, --report.");
   var checks=new List<string>();
   try{
    Directory.CreateDirectory(fixture);
    foreach(string f in new[]{"MouseAim-Settings.ini","Keybindings.ini","Keybindings.schema.json","MouseAim-Settings.ps1","package-info.json","Hud-Style.ini","FOV.ini","MissileGuidance.ini","FrameGeneration.ini"})
     if(File.Exists(Path.Combine(source,f)))File.Copy(Path.Combine(source,f),Path.Combine(fixture,f),true);
    var store=new ConfigStore(fixture);
    double initialCamera=store.State.Values["camera_mode"];checks.Add("Current settings and actual keyboard schema load correctly.");
    bool initialFrame=store.State.FrameGenerationEnabled;
    string framePath=Path.Combine(fixture,"FrameGeneration.ini");
    byte[] initialFrameBytes=File.Exists(framePath)?File.ReadAllBytes(framePath):null;
    var frameState=store.State.Copy();frameState.FrameGenerationEnabled=!initialFrame;
    Check(frameState.Signature()!=store.State.Signature(),"Frame generation missing from dirty state.");
    store.Save(frameState);Check(store.State.FrameGenerationEnabled!=initialFrame,"Frame generation save failed.");
    store.Restore();Check(store.State.FrameGenerationEnabled==initialFrame,"Frame generation restore failed.");
    Check(initialFrameBytes==null?!File.Exists(framePath):initialFrameBytes.SequenceEqual(File.ReadAllBytes(framePath)),"Frame generation restore changed original bytes.");
    Check(!store.Defaults().FrameGenerationEnabled&&!FrameGeneration.Parse(""),"Frame generation enabled by default.");
    string pluginOff="[ConsoleVariables]\r\nr.Streamline.InitializePlugin=0\r\nr.Streamline.DLSSG.Enable=0\r\n";
    Check(FrameGeneration.Serialize(pluginOff,false)==pluginOff,"Disabling changed unrelated plugin setting.");
    Check(FrameGeneration.Serialize(pluginOff,true).Contains("InitializePlugin=1"),"Enabling did not initialize plugin.");
    Reject(()=>FrameGeneration.Parse(pluginOff+"r.Streamline.DLSSG.Enable=1\r\n"),"Duplicate frame generation setting accepted.");
    Reject(()=>FrameGeneration.Parse(pluginOff.Replace("DLSSG.Enable=0","DLSSG.Enable=2")),"Invalid frame generation value accepted.");
    frameState=store.State.Copy();frameState.Values["sensitivity"]=.234;
    File.WriteAllText(framePath,FrameGeneration.Serialize(initialFrameBytes==null?"":Encoding.UTF8.GetString(initialFrameBytes).TrimStart('\uFEFF'),!initialFrame),new UTF8Encoding(false));
    store.Refresh(frameState);Check(frameState.FrameGenerationEnabled!=initialFrame&&frameState.Values["sensitivity"]==.234,"Frame generation refresh discarded unrelated edits.");
    if(initialFrameBytes==null)File.Delete(framePath);else File.WriteAllBytes(framePath,initialFrameBytes);
    store.Load();checks.Add("Frame generation: load, copy/dirty state, on/off save, exact backup restore, default off, plugin initialization, invalid input and concurrent refresh passed.");
    var guidanceState=store.State.Copy();
    foreach(double invalid in new[]{-0.1,1.001,double.NaN,double.PositiveInfinity,.1234}){guidanceState.Values["guidance_MSL"]=invalid;Reject(()=>store.Validate(guidanceState),"Invalid guidance value accepted.");}
    Reject(()=>Guidance.Parse("MSL=0.5",store.State.Copy()),"Partial guidance config accepted.");
    Reject(()=>Guidance.Parse("",store.State.Copy()),"Empty guidance config accepted.");
    guidanceState=store.State.Copy();guidanceState.Values["guidance_MSL"]=.5;guidanceState.Values["guidance_QAAM"]=.7;guidanceState.Values["guidance_EASY"]=.55;
    store.Save(guidanceState);Check(store.State.Values["guidance_QAAM"]==.7,"Guidance save failed.");
    Check(File.Exists(Path.Combine(store.LatestBackup(),"backup.json")),"Guidance backup missing.");
    store.Restore();Check(store.State.Values["guidance_QAAM"]==1,"Guidance restore failed.");
    guidanceState=store.State.Copy();guidanceState.Values["guidance_MSL"]=.5;guidanceState.Values["guidance_QAAM"]=.7;
    string guidePath=Path.Combine(fixture,"MissileGuidance.ini");
    File.WriteAllText(guidePath,System.Text.RegularExpressions.Regex.Replace(File.ReadAllText(guidePath),@"(?m)^MSL=[^\r\n]*","MSL=0.625"));
    store.Refresh(guidanceState);Check(guidanceState.Values["guidance_MSL"]==.625&&guidanceState.Values["guidance_QAAM"]==.7,"Guidance conflict handling failed.");
    store.Load();checks.Add("Guidance: invalid/partial/empty settings rejected; saved values backed up/restored; concurrent changes win without discarding unrelated edits.");
    var state=store.State.Copy();state.Values["sensitivity"]=double.NaN;Reject(()=>store.Validate(state),"NaN accepted.");
    state=store.State.Copy();state.Values["hud_fps"]=120.5;Reject(()=>store.Validate(state),"Fractional frequency accepted.");
    state=store.State.Copy();state.Values["camera_mode"]=3;Reject(()=>store.Validate(state),"Unknown camera mode accepted.");
    state=store.State.Copy();state.Keys["free_look"]=state.Keys["pitch_up"];Reject(()=>store.Validate(state),"Duplicate key accepted.");
    state=store.State.Copy();state.Color="#12345";Reject(()=>store.Validate(state),"Malformed color accepted.");
    state=store.State.Copy();state.Values["fov_cockpit"]=20;Reject(()=>store.Validate(state),"FOV below 40 accepted.");
    state=store.State.Copy();state.Values["fov_hud"]=131;Reject(()=>store.Validate(state),"FOV above 130 accepted.");
    checks.Add("Ranges, integer settings, unsupported camera modes, key conflicts and malformed colors rejected.");
    var originals=ConfigStore.Files.ToDictionary(f=>f,f=>File.Exists(Path.Combine(fixture,f))?File.ReadAllBytes(Path.Combine(fixture,f)):null);
    state=store.State.Copy();state.Values["sensitivity"]=.123;state.Color="#8CFFB0";
    state.Values["fov_cockpit"]=120;state.Values["fov_hud"]=90;state.Values["fov_third_person"]=0;
    store.Save(state);Check(store.State.Values["sensitivity"]==.123&&store.State.Color=="#8CFFB0","Save/read round trip failed.");
    Check(store.State.Values["camera_mode"]==initialCamera,"Save changed selected camera mode.");
    Check(store.State.Values["fov_cockpit"]==120&&store.State.Values["fov_hud"]==90&&store.State.Values["fov_third_person"]==0,"FOV save/read round trip failed.");
    Check(File.ReadAllText(Path.Combine(fixture,"MouseAim-Settings.ini")).Contains("; Reference gun cross"),"INI comments lost.");
    Check(store.LatestBackup()!=null,"No automatic backup.");
    checks.Add("Three-file save round trip preserves comments and cockpit mode; automatic backup created.");
    store.Restore();
    foreach(string f in ConfigStore.Files){
     string p=Path.Combine(fixture,f);
     Check(originals[f]==null?!File.Exists(p):originals[f].SequenceEqual(File.ReadAllBytes(p)),"Restore bytes differ: "+f);
    }
    checks.Add("Backup restore reproduces exact previous bytes (including missing optional style file).");
    store=new ConfigStore(fixture);
    File.AppendAllText(Path.Combine(fixture,"MouseAim-Settings.ini"),"\r\n; external edit\r\n");
    state=store.State.Copy();state.Values["sensitivity"]=.2;
    Reject(()=>store.Save(state),"Concurrent external modification was overwritten.");
    Check(File.ReadAllText(Path.Combine(fixture,"MouseAim-Settings.ini")).Contains("; external edit"),"External edit lost.");
    checks.Add("External modifications are detected before writing, preventing stale overwrites.");
    store=new ConfigStore(fixture);state=store.State.Copy();
    state.Values["sensitivity"]=.25;state.Values["free_look_zoom"]=2.5;
    string settingPath=Path.Combine(fixture,"MouseAim-Settings.ini");
    string external=System.Text.RegularExpressions.Regex.Replace(File.ReadAllText(settingPath),@"(?m)^sensitivity=[^\r\n]*","sensitivity=0.33");
    File.WriteAllText(settingPath,external);
    Check(store.Refresh(state),"External settings did not refresh.");
    Check(state.Values["sensitivity"]==.33&&state.Values["free_look_zoom"]==2.5,"Game priority or unrelated pending edit preservation failed.");
    store.Save(state);Check(store.State.Values["sensitivity"]==.33,"Refreshed game sensitivity overwritten.");
    state=store.State.Copy();state.Values["sensitivity"]=.5;
    string tagged=System.Text.RegularExpressions.Regex.Replace(File.ReadAllText(settingPath),@"(?m)^; AC8 runtime sensitivity [^\r\n]*","");
    File.WriteAllText(settingPath,tagged+"\r\n; AC8 runtime sensitivity test-session 2\r\n");
    store.Refresh(state);Check(state.Values["sensitivity"]==.33,"Same-value game event did not override a pending menu edit.");
    checks.Add("Game settings win conflicts; unrelated pending menu edits survive; same-value runtime events also win.");
    File.WriteAllText(report,"PASS\r\n"+string.Join("\r\n",checks),Encoding.UTF8);return 0;
   }catch(Exception ex){File.WriteAllText(report,"FAIL\r\n"+ex.ToString()+"\r\n"+string.Join("\r\n",checks),Encoding.UTF8);return 1;}
  }
 }
}
