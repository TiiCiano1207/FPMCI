using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Forms=System.Windows.Forms;
namespace AC8Settings {
 public sealed partial class SettingsWindow {
  string gamePath="",steamPath="",missileMode="guidance",launchOption="";
  bool busy,modDisabled,watchLaunchStatus;
  string[] gameCandidates=new string[0],steamCandidates=new string[0];
  TextBox gameInput,steamInput,optionInput,logInput;
  ComboBox featureInput;
  readonly List<string> operationLog=new List<string>();
  void LoadInstallation(){
   gameInput=null;steamInput=null;optionInput=null;featureInput=null;
   gamePath=ReadPackage("game-path.txt");steamPath=ReadPackage("steam-path.txt");launchOption=ReadPackage("Steam-Launch-Option.txt");
   savedSteamLaunch=ReadPackage("Launcher-Options.ini")!="steam_launch=0";
   ((CheckBox)Window.FindName("SteamLaunch")).IsChecked=savedSteamLaunch;
   string feature=ReadPackage("features.ini");
   missileMode=feature.Contains("missile_mode=none")||feature.Contains("missile_enhancement=0")?"none":"guidance";
  }
  void RefreshHeader(){
   ((TextBlock)Window.FindName("HeaderGame")).Text=File.Exists(Path.Combine(gamePath,"Game","Binaries","Win64","AceCombat8.exe"))?"已定位":"待定位";
   modDisabled=File.Exists(Path.Combine(store.Root,"mod-disabled.flag"))||(File.Exists(Path.Combine(Path.GetDirectoryName(store.Root),"AC8-Managed-Packages.json"))&&File.Exists(Path.Combine(Path.GetDirectoryName(store.Root),"mod-disabled.flag")));
   ((TextBlock)Window.FindName("HeaderMode")).Text=modDisabled?"已停用":"已启用";
   ((TextBlock)Window.FindName("HeaderProfile")).Text=missileMode=="none"?"鼠标飞控":"导弹模块";
   ((TextBlock)Window.FindName("HeaderVersion")).Text=store.Version;
  }
  string ReadPackage(string name){string p=Path.Combine(store.Root,name);return File.Exists(p)?File.ReadAllText(p).Trim().Trim('\uFEFF'):"";}
  void CommitInstallFields(){
   if(gameInput!=null)gamePath=gameInput.Text;
   if(steamInput!=null)steamPath=steamInput.Text;
   if(featureInput!=null&&featureInput.SelectedIndex>=0)missileMode=new[]{"guidance","none"}[featureInput.SelectedIndex];
  }
  Button ActionButton(string label,Action click,bool primary=false){
   var b=new Button{Content=label,Padding=new Thickness(14,8,14,8),Margin=new Thickness(0,0,9,9),FontSize=12};
   if(primary)b.Tag="primary";b.Click+=(s,e)=>click();return b;
  }
  void Actions(params Button[] buttons){var wrap=new WrapPanel{Margin=new Thickness(0,12,0,3)};foreach(var b in buttons)wrap.Children.Add(b);body.Children.Add(wrap);}
  void InstallationPage(){
   gameInput=null;steamInput=null;featureInput=null;optionInput=null;
   PathRow("游戏位置","可以选择游戏根目录、Win64 目录或 AceCombat8.exe。",gamePath,false);
   PathRow("Steam 程序","选择 Steam 安装目录中的 steam.exe。",steamPath,true);
   Actions(ActionButton("自动定位",()=>RunOperation("Discover")),ActionButton("检查环境",()=>RunOperation("Check")),ActionButton("校验安装包",()=>RunOperation("CheckPackage")));
   Section("选择安装内容","两种方案都包含鼠标飞控；导弹模块按你的选择启用。");
   var row=Row("安装方案","导弹模块包含比例引导与按弹种选择的近炸增强。");
   featureInput=new ComboBox{VerticalAlignment=VerticalAlignment.Center};
   foreach(string s in new[]{"飞控 + 导弹模块","仅鼠标飞控"})featureInput.Items.Add(s);
   featureInput.SelectedIndex=Array.IndexOf(new[]{"guidance","none"},missileMode);
   featureInput.SelectionChanged+=(s,e)=>{if(featureInput.SelectedIndex>=0){missileMode=new[]{"guidance","none"}[featureInput.SelectedIndex];RefreshHeader();}};
   Grid.SetColumn(featureInput,1);row.Children.Add(featureInput);

   Section("Steam 启动选项","首次安装或移动 MOD 文件夹后：保存方案，再将下面这一行粘贴到 Steam → 游戏属性 → 启动选项。");
   optionInput=new TextBox{Text=launchOption,IsReadOnly=true,TextWrapping=TextWrapping.Wrap,FontFamily=numbers,FontSize=12,MinHeight=62};
   body.Children.Add(optionInput);
   Actions(ActionButton("复制启动选项",()=>{if(string.IsNullOrWhiteSpace(launchOption)){SetStatus("先保存安装方案，工具才会生成正确的启动选项。",true);return;}try{Clipboard.SetText(launchOption);SetStatus("启动选项已复制 · 请粘贴到 Steam 的游戏属性中");}catch(Exception ex){SetStatus(ex.Message,true);}}));
   Note("安装方案保存后，由 Steam 完成云同步，再自动部署 MOD。游戏退出后保留原有清理流程；本工具不会直接改写 Steam 账户配置。");
   Logs();
  }
  void PathRow(string label,string hint,string value,bool steam){
   var row=Row(label,hint);
   row.ColumnDefinitions[1].Width=new GridLength(Math.Max(240,Math.Min(360,(Window.Width-274)*.52)));
   var controls=new Grid();controls.ColumnDefinitions.Add(new ColumnDefinition());controls.ColumnDefinitions.Add(new ColumnDefinition{Width=GridLength.Auto});
   var input=new TextBox{Text=value,FontSize=12,MinHeight=40,VerticalAlignment=VerticalAlignment.Center};
   var browse=new Button{Content="浏览",Padding=new Thickness(11,7,11,7),Margin=new Thickness(8,0,0,0),FontSize=12};
   if(steam)steamInput=input;else gameInput=input;
   input.TextChanged+=(s,e)=>{if(steam)steamPath=input.Text;else gamePath=input.Text;RefreshHeader();};
   browse.Click+=(s,e)=>{
    if(steam){var dialog=new Microsoft.Win32.OpenFileDialog{Title="选择 steam.exe",Filter="Steam 程序|steam.exe",CheckFileExists=true};if(dialog.ShowDialog(Window)==true)input.Text=dialog.FileName;}
    else{using(var dialog=new Forms.FolderBrowserDialog{Description="选择游戏根目录或 Win64 文件夹",ShowNewFolderButton=false})if(dialog.ShowDialog()==Forms.DialogResult.OK)input.Text=dialog.SelectedPath;}
   };
   controls.Children.Add(input);Grid.SetColumn(browse,1);controls.Children.Add(browse);Grid.SetColumn(controls,1);row.Children.Add(controls);
   var candidates=steam?steamCandidates:gameCandidates;
   if(candidates.Length>1){
    var choice=new ComboBox{Margin=new Thickness(0,9,0,4),FontSize=12};foreach(string c in candidates)choice.Items.Add(c);
    choice.SelectionChanged+=(s,e)=>{if(choice.SelectedItem!=null)input.Text=choice.SelectedItem.ToString();};body.Children.Add(choice);
   }
  }
  void MaintenancePage(){
   Section("附加 MOD","拖动模组行，或使用上移、下移调整加载顺序。");
   Actions(ActionButton("管理附加 MOD",ShowExtraMods,true));
   var summary=new StackPanel();
   try{
    var mods=ReadExtraMods();
    var label=Text("已添加 "+mods.Length+" 个 MOD",12,"#496878");
    label.Margin=new Thickness(0,0,0,5);
    summary.Children.Add(label);
    if(mods.Length==0)summary.Children.Add(Text("暂无附加 MOD",12,"#496878"));
    else{
     var rows=new StackPanel();
     foreach(var mod in mods)rows.Children.Add(DraggableModRow(mod,mods,async (source,target,before)=>{
      if(busy)return;
      SetBusy(true);
      try{
       var req=new OperationRequest{Root=store.Root,Action=before?"ExtraBefore":"ExtraAfter",ExtraName=source,ExtraPath=target};
       var result=await Task.Run(()=>Operations.Run(req,null));
       if(page==6)ShowPage(page);
       SetOperationStatus(result);
      }catch(Exception ex){SetStatus(ex.Message,true);}finally{SetBusy(false);}
     }));
     summary.Children.Add(new ScrollViewer{Content=rows,MaxHeight=112,VerticalScrollBarVisibility=ScrollBarVisibility.Auto});
    }
   }catch(Exception ex){summary.Children.Add(Text(ex.Message,12,"#AF3928"));}
   body.Children.Add(summary);

   Section(modDisabled?"模组当前已停用":"模组当前已启用","只切换本整合包的启动模式，保留游戏原文件。");
   Actions(ActionButton("启用模组",()=>RunOperation("Enable")),ActionButton("停用模组",()=>RunOperation("Disable")),ActionButton("检查原版启动条件",()=>RunOperation("CheckOriginal")));
   Note("启停前需退出游戏。原有检查会确认加载器归属与会话状态，不会删除未知 MOD 文件。");
   Section("清理与恢复","正常退出会自动清理；异常退出后，可在这里恢复。");
   Actions(ActionButton("清理当前会话",()=>RunOperation("Cleanup")),ActionButton("备份并清理历史残留",()=>{
    CommitInstallFields();
    if(MessageBox.Show(Window,"将先备份、校验，再清理可确认属于本整合包的残留。\n\n请确认这些文件来自本 MOD；其他或未知 MOD 会被保留。\n\n游戏位置："+gamePath,"备份并清理历史残留",MessageBoxButton.YesNo,MessageBoxImage.Question)==MessageBoxResult.Yes)RunOperation("Recover",true);
   }));
   Actions(ActionButton("打开清理备份",()=>OpenFolder("cleanup-backups")),ActionButton("打开设置备份",()=>OpenFolder("settings-backups")));
   Logs();
  }
  bool IsManagedModule(string name){
   return IsEnhancedHud(name)||AcePilotsSettings.IsIntegrated(store.Root,name);
  }
  ExtraModEntry[] ReadExtraMods(){
   var folder=new DirectoryInfo(Path.Combine(store.Root,"ue4ss-mods"));
   if(!folder.Exists)return new ExtraModEntry[0];
   if((folder.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("附加 MOD 库是文件系统链接，请检查目录。");
   var orderPath=Path.Combine(store.Root,"ExtraModOrder.txt");
   var ranks=new Dictionary<string,int>(StringComparer.OrdinalIgnoreCase);
   if(File.Exists(orderPath))foreach(var name in File.ReadAllLines(orderPath))if(!ranks.ContainsKey(name))ranks.Add(name,ranks.Count);
   return folder.GetDirectories().Where(d=>!IsManagedModule(d.Name))
    .OrderBy(d=>{int rank;return ranks.TryGetValue(d.Name.TrimStart('_'),out rank)?rank:int.MaxValue;})
    .ThenBy(d=>d.Name,StringComparer.OrdinalIgnoreCase)
    .Select(d=>new ExtraModEntry{Name=d.Name,Enabled=!d.Name.StartsWith("_",StringComparison.Ordinal)}).ToArray();
  }
  Border ExtraModRow(ExtraModEntry mod,params Button[] actions){
   var line=new DockPanel{LastChildFill=true};
   foreach(var button in actions.Reverse()){
    button.Margin=new Thickness(8,0,0,0);
    DockPanel.SetDock(button,Dock.Right);line.Children.Add(button);
   }
   var state=Text(mod.Enabled?"已启用":"已停用",12,mod.Enabled?"#086E89":"#496878");
   state.Margin=new Thickness(14,0,4,0);state.VerticalAlignment=VerticalAlignment.Center;
   DockPanel.SetDock(state,Dock.Right);line.Children.Add(state);
   var name=Text(mod.Name.TrimStart('_'),13);
   name.TextWrapping=TextWrapping.NoWrap;name.TextTrimming=TextTrimming.CharacterEllipsis;
   name.ToolTip=mod.Name;name.VerticalAlignment=VerticalAlignment.Center;
   line.Children.Add(name);
   return new Border{Child=line,BorderBrush=Brush("#BED3DD"),BorderThickness=new Thickness(0,0,0,1),Padding=new Thickness(9,6,9,6),MinHeight=33};
  }
  static bool FocusModRow(DependencyObject root,string name){
   var border=root as Border;
   if(border!=null && border.Focusable && Equals(border.Tag,name))return border.Focus();
   for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++)
    if(FocusModRow(VisualTreeHelper.GetChild(root,i),name))return true;
   return false;
  }
  Border DraggableModRow(ExtraModEntry mod,ExtraModEntry[] mods,Func<string,string,bool,Task> save,params Button[] actions){
   int index=Array.IndexOf(mods,mod);
   Func<int,Task> step=dir=>save(mod.Name,mods[index+dir].Name,dir<0);
   var up=ActionButton("上移",async ()=>await step(-1));
   var down=ActionButton("下移",async ()=>await step(1));
   up.IsEnabled=index>0;down.IsEnabled=index+1<mods.Length;
   var row=ExtraModRow(mod,new[]{up,down}.Concat(actions).ToArray());
   row.Focusable=true;row.Tag=mod.Name;
   row.KeyDown+=async (s,e)=>{
    if(e.OriginalSource!=row)return;
    int dir=e.Key==Key.Up?-1:e.Key==Key.Down?1:0;
    if(dir==0)return;
    e.Handled=true;if(index+dir<0||index+dir>=mods.Length)return;
    var host=(Window)Window.GetWindow(row);
    await step(dir);
    if(host!=null)FocusModRow(host,mod.Name);
   };
   var panel=(DockPanel)row.Child;
   var grip=Text("☰",15,"#496878");grip.Margin=new Thickness(0,0,9,0);
   DockPanel.SetDock(grip,Dock.Left);panel.Children.Insert(0,grip);
   row.Background=Brushes.Transparent;row.AllowDrop=true;
   row.Cursor=Cursors.SizeNS;row.ToolTip="按住拖动，调整加载顺序";
   foreach(var button in actions)button.Cursor=Cursors.Hand;
   Point? start=null;
   row.MouseLeftButtonDown+=(s,e)=>{row.Focus();start=e.GetPosition(row);row.CaptureMouse();e.Handled=true;};
   row.LostMouseCapture+=(s,e)=>start=null;
   row.MouseLeftButtonUp+=(s,e)=>{if(row.IsMouseCaptured)row.ReleaseMouseCapture();};
   row.MouseMove+=(s,e)=>{
    if(!start.HasValue||e.LeftButton!=MouseButtonState.Pressed)return;
    var delta=e.GetPosition(row)-start.Value;
    if(Math.Abs(delta.X)<SystemParameters.MinimumHorizontalDragDistance && Math.Abs(delta.Y)<SystemParameters.MinimumVerticalDragDistance)return;
    row.ReleaseMouseCapture();
    DragDrop.DoDragDrop(row,new DataObject("FPMCI.ModOrder",mod.Name),DragDropEffects.Move);
   };
   var brush=row.BorderBrush;var thickness=row.BorderThickness;
   Action reset=()=>{row.BorderBrush=brush;row.BorderThickness=thickness;};
   DragEventHandler over=(s,e)=>{
    if(!e.Data.GetDataPresent("FPMCI.ModOrder"))return;
    bool valid=(string)e.Data.GetData("FPMCI.ModOrder")!=mod.Name;
    e.Handled=true;e.Effects=valid?DragDropEffects.Move:DragDropEffects.None;
    if(!valid){reset();return;}
    row.BorderBrush=Brush("#086E89");row.BorderThickness=e.GetPosition(row).Y<row.ActualHeight/2?new Thickness(0,2,0,0):new Thickness(0,0,0,2);
   };
   row.PreviewDragEnter+=over;row.PreviewDragOver+=over;
   row.DragLeave+=(s,e)=>reset();
   row.PreviewDrop+=async (s,e)=>{
    if(!e.Data.GetDataPresent("FPMCI.ModOrder"))return;
    string source=e.Data.GetData("FPMCI.ModOrder") as string;
    bool before=e.GetPosition(row).Y<row.ActualHeight/2;
    e.Handled=true;reset();
    if(source!=null && source!=mod.Name)await save(source,mod.Name,before);
   };
   return row;
  }
  void ShowExtraMods(){
   if(busy||store==null||!CommitEditors())return;
   CreateExtraModsWindow().ShowDialog();
   RefreshConfiguration();
   ShowPage(page);
  }
  Window CreateExtraModsWindow(){
   var dialog=new Window{Title="FPMCI · 附加 MOD",Owner=Window,WindowStartupLocation=WindowStartupLocation.CenterOwner,
    Width=790,Height=610,MinWidth=620,MinHeight=500,ShowInTaskbar=false,
    Background=Window.Background,Foreground=Window.Foreground,FontFamily=Window.FontFamily,FontSize=Window.FontSize,
    Icon=Window.Icon,UseLayoutRounding=true,AllowDrop=true};
   dialog.Resources.MergedDictionaries.Add(Window.Resources);
   var layout=new DockPanel{LastChildFill=true};
   dialog.Content=new Border{Child=layout,Padding=new Thickness(24),Background=Window.Background};
   var header=new StackPanel{Margin=new Thickness(0,0,0,16)};
   var title=Text("附加 UE4SS MOD",23);title.FontWeight=FontWeights.SemiBold;header.Children.Add(title);
   var hint=Text("拖动 MOD 名称到目标行的上方或下方。下次启动时，已启用的 MOD 从上到下加载。",13,"#496878");
   hint.Margin=new Thickness(0,7,0,0);header.Children.Add(hint);
   DockPanel.SetDock(header,Dock.Top);layout.Children.Add(header);
   var footer=new StackPanel{Margin=new Thickness(0,14,0,0)};
   DockPanel.SetDock(footer,Dock.Bottom);layout.Children.Add(footer);
   var help=Text("支持 ZIP 或已解压的 UE4SS MOD 文件夹。MOD 自带的 Pak 和 IoStore 资源会随 MOD 部署。移除的 MOD 可从备份目录重新导入。",12,"#496878");
   footer.Children.Add(help);
   var message=Text("改动将在下次启动时生效。",12,"#496878");message.Margin=new Thickness(0,9,0,6);
   footer.Children.Add(new ScrollViewer{Content=message,MaxHeight=64,VerticalScrollBarVisibility=ScrollBarVisibility.Auto});
   var bar=new DockPanel{LastChildFill=true,Margin=new Thickness(0,3,0,0)};
   footer.Children.Add(bar);
   var close=ActionButton("完成",()=>dialog.Close(),true);
   DockPanel.SetDock(close,Dock.Right);bar.Children.Add(close);
   var commands=new WrapPanel();bar.Children.Add(commands);
   var list=new StackPanel();
   var empty=Text("尚未添加 MOD。可选择 ZIP 或文件夹，也可以拖入窗口。",13,"#496878");
   empty.HorizontalAlignment=HorizontalAlignment.Center;empty.VerticalAlignment=VerticalAlignment.Center;empty.TextAlignment=TextAlignment.Center;
   empty.Margin=new Thickness(18);
   var listSurface=new Grid();
   listSurface.Children.Add(new ScrollViewer{Content=list,VerticalScrollBarVisibility=ScrollBarVisibility.Auto});
   listSurface.Children.Add(empty);
   layout.Children.Add(new Border{Child=listSurface,Background=Brush("#F8FBFC"),BorderBrush=Brush("#BED3DD"),BorderThickness=new Thickness(1)});
   bool working=false;
   Action<string,bool> show=(text,error)=>{message.Text=text;message.Foreground=Brush(error?"#AF3928":"#496878");};
   Action<ExtraModEntry[]> render=null;
   Func<string,string,string,Task> run=async (action,path,name)=>{
    if(working)return;
    working=true;commands.IsEnabled=list.IsEnabled=close.IsEnabled=false;show("正在处理附加 MOD…",false);
    try{
     var request=new OperationRequest{Action=action,Root=store.Root,ExtraPath=path,ExtraName=name};
     var result=await Task.Run(()=>Operations.Run(request,null));
     if(action=="ExtraPreview"&&result.Success){
      if(MessageBox.Show(dialog,result.Message,"确认导入附加 MOD",MessageBoxButton.OKCancel,MessageBoxImage.Question)!=MessageBoxResult.OK){
       show("已取消导入。",false);return;
      }
      request.Action="ExtraImport";request.ExtraToken=result.ExtraToken;
      result=await Task.Run(()=>Operations.Run(request,null));
     }
     if(result.ExtraMods!=null)render(result.ExtraMods);
     show(result.Message,!result.Success);
    }catch(Exception ex){show(ex.Message,true);}
    finally{working=false;commands.IsEnabled=list.IsEnabled=close.IsEnabled=true;}
   };
   render=mods=>{
    mods=mods.Where(mod=>!IsManagedModule(mod.Name)).ToArray();
    list.Children.Clear();
    empty.Visibility=mods.Length==0?Visibility.Visible:Visibility.Collapsed;
    foreach(var mod in mods){
     var toggle=ActionButton(mod.Enabled?"停用":"启用",async ()=>await run(mod.Enabled?"ExtraDisable":"ExtraEnable",null,mod.Name));
     var remove=ActionButton("移到备份",async ()=>{
      if(MessageBox.Show(dialog,"将 "+mod.Name+" 移到附加 MOD 备份目录。","移除附加 MOD",MessageBoxButton.OKCancel)==MessageBoxResult.OK)
       await run("ExtraRemove",null,mod.Name);
     });
    list.Children.Add(DraggableModRow(mod,mods,(source,target,before)=>run(before?"ExtraBefore":"ExtraAfter",target,source),toggle,remove));
    }
   };
   commands.Children.Add(ActionButton("添加 ZIP…",async ()=>{
    var picker=new Microsoft.Win32.OpenFileDialog{Title="选择附加 MOD",Filter="ZIP 压缩包|*.zip",CheckFileExists=true};
    if(picker.ShowDialog(dialog)==true)await run("ExtraPreview",picker.FileName,null);
   }));
   commands.Children.Add(ActionButton("添加文件夹…",async ()=>{
    using(var picker=new Forms.FolderBrowserDialog{Description="选择附加 MOD 文件夹",ShowNewFolderButton=false})
     if(picker.ShowDialog()==Forms.DialogResult.OK)await run("ExtraPreview",picker.SelectedPath,null);
   }));
   commands.Children.Add(ActionButton("打开 MOD 库",()=>{
    string path=Path.Combine(store.Root,"ue4ss-mods");
    if(!Directory.Exists(path)){show("导入后即可打开 MOD 库。",false);return;}
    try{Process.Start(new ProcessStartInfo("explorer.exe",Operations.Quote(path)){UseShellExecute=true});}
    catch(Exception ex){show(ex.Message,true);}
   }));
   dialog.DragOver+=(s,e)=>{
    var paths=e.Data.GetData(DataFormats.FileDrop) as string[];
    e.Effects=!working&&paths!=null&&paths.Length==1&&(Directory.Exists(paths[0])||Path.GetExtension(paths[0]).Equals(".zip",StringComparison.OrdinalIgnoreCase))
     ?DragDropEffects.Copy:DragDropEffects.None;e.Handled=true;
   };
   dialog.Drop+=async (s,e)=>{
    var paths=e.Data.GetData(DataFormats.FileDrop) as string[];
    if(paths!=null&&paths.Length==1)await run("ExtraPreview",paths[0],null);
    e.Handled=true;
   };
   dialog.PreviewKeyDown+=(s,e)=>{if(e.Key==Key.Escape&&!working){e.Handled=true;dialog.Close();}};
   dialog.Closing+=(s,e)=>{if(working)e.Cancel=true;};
   try{render(ReadExtraMods());}catch(Exception ex){show(ex.Message,true);}
   return dialog;
  }
  void HelpPage(){
   Section("安装 MOD","将完整文件夹解压到游戏目录之外，双击 AC8Workbench.exe。");
   Note("1. 在“安装与启动”中选择游戏位置、Steam 程序和安装方案。\n2. 点击左下角“保存设置”。\n3. 首次使用或移动文件夹后，复制启动选项，粘贴到 Steam → 游戏属性 → 启动选项。\n4. 点击右下角“开始游戏”。游戏退出后会自动清理本次部署。");
   Actions(ActionButton("打开安装说明",()=>OpenDocument("docs/INSTALL.md")));
  }
  void Logs(){
   Section("操作日志","后台处理时这里会持续显示输出。");
   logInput=new TextBox{Text=string.Join(Environment.NewLine,operationLog),IsReadOnly=true,TextWrapping=TextWrapping.Wrap,MinHeight=115,MaxHeight=240,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,FontFamily=numbers,FontSize=12};
   body.Children.Add(logInput);
  }
  void OpenFolder(string relative){
   string folder=Path.Combine(store.Root,relative);
   if(!Directory.Exists(folder)){SetStatus("这个目录尚未生成："+relative);return;}
   try{Process.Start(new ProcessStartInfo("explorer.exe",Operations.Quote(folder)){UseShellExecute=true});}catch(Exception ex){SetStatus(ex.Message,true);}
  }
  void OpenDocument(string relative){
   string file=Path.Combine(store.Root,relative.Replace('/',Path.DirectorySeparatorChar));
   if(!File.Exists(file)){SetStatus("说明文件不存在："+relative,true);return;}
   try{Process.Start(new ProcessStartInfo("notepad.exe",Operations.Quote(file)){UseShellExecute=true});}catch(Exception ex){SetStatus(ex.Message,true);}
  }
  void SetBusy(bool value){
   busy=value;body.IsEnabled=nav.IsEnabled=!value;
   ((Button)Window.FindName("ChoosePackage")).IsEnabled=!value;((Button)Window.FindName("Reload")).IsEnabled=!value;
   ((Button)Window.FindName("StartGame")).IsEnabled=!value;
   ((CheckBox)Window.FindName("SteamLaunch")).IsEnabled=!value;
   save.IsEnabled=!value&&(page==5||Dirty());defaults.IsEnabled=!value;restore.IsEnabled=!value&&store.LatestBackup()!=null;
   ((ProgressBar)Window.FindName("Busy")).Visibility=value?Visibility.Visible:Visibility.Collapsed;
  }
  void SetOperationStatus(OperationResult result){
   SetStatus(result.Title+" · "+result.Message,!result.Success);
   watchLaunchStatus=result.Code=="GAME_RUNNING";
  }
  void RefreshLaunchStatus(){
   if(!watchLaunchStatus||busy||store==null)return;
   var games=Process.GetProcessesByName("AceCombat8");
   bool running=games.Length!=0;
   foreach(var game in games)game.Dispose();
   if(running)return;
   if(File.Exists(Path.Combine(store.Root,"active-session.json"))){
    SetStatus("游戏已退出 · 上次会话待恢复，再次启动时会等待或继续恢复");
    watchLaunchStatus=true;
   }else SetStatus("游戏已退出 · 可再次点击开始游戏，启动器会等待后台整理完成");
  }
  async void RunOperation(string action,bool confirm=false){
   if(busy||store==null)return;
   CommitInstallFields();if(!CommitEditors())return;
   RefreshConfiguration();
   if((action=="Start"||action=="Save")&&Dirty()&&!Save())return;
   bool steam=((CheckBox)Window.FindName("SteamLaunch")).IsChecked==true;
   if(action=="Start"&&!steam)action="StartDirect";
   var request=new OperationRequest{Action=action,Root=store.Root,GamePath=gamePath,SteamPath=steamPath,MissileMode=missileMode,ConfirmRecovery=confirm};
   var labels=new Dictionary<string,string>{{"Discover","自动定位"},{"Check","环境检查"},{"Save","保存安装方案"},{"Start","开始游戏"},{"StartDirect","开始游戏"},{"Recover","历史残留清理"},{"Cleanup","会话清理"},{"Enable","启用模组"},{"Disable","停用模组"},{"CheckOriginal","原版启动检查"},{"CheckPackage","安装包校验"}};
   SetBusy(true);SetStatus("正在处理："+labels[action]+" · 完成前请勿关闭工具");
   try{
    if(action=="Start"||action=="StartDirect"){
     bool installationChanged=ReadPackage("game-path.txt")!=gamePath||ReadPackage("steam-path.txt")!=steamPath||string.IsNullOrWhiteSpace(launchOption);
     string storedFeature=ReadPackage("features.ini");
     string storedMode=storedFeature.Contains("missile_mode=none")||storedFeature.Contains("missile_enhancement=0")?"none":"guidance";
     if(installationChanged||storedMode!=missileMode){
      var installation=await Task.Run(()=>Operations.Run(new OperationRequest{Action="Save",Root=store.Root,GamePath=gamePath,SteamPath=steamPath,MissileMode=missileMode},null));
      if(!installation.Success){SetBusy(false);SetOperationStatus(installation);return;}
      if(!string.IsNullOrEmpty(installation.GameRoot)){gamePath=installation.GameRoot;request.GamePath=gamePath;}
      if(!string.IsNullOrEmpty(installation.Option))launchOption=installation.Option;
     }
    }
    var result=await Task.Run(()=>Operations.Run(request,line=>Window.Dispatcher.BeginInvoke(new Action(()=>{
     operationLog.Add(line);if(operationLog.Count>600)operationLog.RemoveAt(0);
     if(logInput!=null){logInput.Text=string.Join(Environment.NewLine,operationLog);logInput.ScrollToEnd();}
    }))));
    if(!string.IsNullOrEmpty(result.GameRoot))gamePath=result.GameRoot;
    if(!string.IsNullOrEmpty(result.SteamPath))steamPath=result.SteamPath;
    if(result.GameCandidates!=null)gameCandidates=result.GameCandidates;
    if(result.SteamCandidates!=null)steamCandidates=result.SteamCandidates;
    if(!string.IsNullOrEmpty(result.Option))launchOption=result.Option;
    SetBusy(false);ShowPage(page,action=="Save");SetOperationStatus(result);
   }catch(Exception ex){SetBusy(false);SetStatus(ex.Message,true);}
  }
 }
}
