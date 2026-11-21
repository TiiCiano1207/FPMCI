using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace AC8Settings {
 static class AcePilotsSettings {
  internal const string ModName="AcePilotsMod";
  internal const string Title="敌方AI增强";
  internal const string FileName="acepilots.ini";
  internal const int Page=9;
  internal const int FlareLimitIndex=17;
  internal const int DefaultFlareLimit=9;

  static readonly string[] keys={
   "ForceRank","SkilledBoost","TopAceBoost","WeakDivide","Rank5Odds","Agility",
   "Missiles","BlackoutBonus","IgnoreAttackQueue","ForceFlares","ForceEvade","ForceTaunts",
   "FromDifficulty","AirOnly","IncludeAllies","ScriptBias","ScriptUnused","FlareMaxTotal"
  };
  internal static readonly string[] PresetLabels={"关闭","全员 5 级","强化 2","强化 3","强化 4","极限"};
  static readonly string[] presetNames={"Off","AllRank5","Boosted2","Boosted3","Boosted4","Max"};
  static readonly double[][] presets={
   new double[]{0,1,1,1,0,1,2,0,0,0,0,0},
   new double[]{5,1,1,1,0,1,2,0,0,0,0,0},
   new double[]{0,2,2,2,0,1,2,0,0,0,0,0},
   new double[]{0,3,3,3,0,1,2,0,0,0,0,0},
   new double[]{0,4,4,4,0,1,2,0,0,0,0,0},
   new double[]{5,2,20,1000,1,1.5,4,5,1,1,1,1}
  };
  static readonly Regex entry=new Regex(@"(?m)^([ \t\uFEFF]*)([A-Za-z][A-Za-z0-9]*)([ \t]*=[ \t]*)([^;\r\n#]*?)([ \t]*[;#][^\r\n]*|[ \t]*)(?=\r?$)");
  static readonly CultureInfo culture=CultureInfo.InvariantCulture;

  internal static bool IsIntegrated(string root,string name){
   return string.Equals(name.TrimStart('_'),ModName,StringComparison.OrdinalIgnoreCase)
    && File.Exists(Path.Combine(root,"ue4ss-mods",name,"acepilots_hook-26002268.dll"));
  }
  internal static string FindInstalled(string root){
   return new[]{ModName,"_"+ModName}.FirstOrDefault(name=>IsIntegrated(root,name));
  }
  internal static string ConfigPath(string root){
   var name=FindInstalled(root);
   return name==null?null:Path.Combine(root,"ue4ss-mods",name,FileName);
  }
  internal static double[] Defaults(){
   return presets[0].Concat(new double[]{4,1,0,0,0,DefaultFlareLimit}).ToArray();
  }
  internal static void ApplyPreset(double[] settings,int preset){
   Array.Copy(presets[preset],settings,presets[preset].Length);
  }
  internal static int PresetIndex(double[] settings){
   return Array.FindIndex(presets,preset=>preset.SequenceEqual(settings.Take(preset.Length)));
  }
  internal static bool TryParseFlareLimit(string text,out int limit){
   return int.TryParse(text.Trim(),NumberStyles.None,culture,out limit);
  }
  internal static double[] Read(byte[] data){
   var settings=Defaults();
   if(data==null)return settings;
   foreach(Match match in entry.Matches(Encoding.UTF8.GetString(data))){
    int index=Array.FindIndex(keys,key=>string.Equals(key,match.Groups[2].Value,StringComparison.OrdinalIgnoreCase));
    if(index==FlareLimitIndex){
     int limit;
     settings[index]=TryParseFlareLimit(match.Groups[4].Value,out limit)?limit:DefaultFlareLimit;
     continue;
    }
    double value;
    if(index>=0&&double.TryParse(match.Groups[4].Value,NumberStyles.Float,culture,out value)&&!double.IsNaN(value)&&!double.IsInfinity(value))
     settings[index]=value;
   }
   return settings;
  }
  internal static byte[] Write(byte[] data,double[] settings){
   int preset=PresetIndex(settings);
   var values=keys.Select((key,index)=>new{key,value=settings[index].ToString("R",culture)})
    .ToDictionary(item=>item.key,item=>item.value,StringComparer.OrdinalIgnoreCase);
   values.Add("Preset",preset<0?"Custom":presetNames[preset]);
   var present=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   string text=data==null?"":Encoding.UTF8.GetString(data);
   text=text.Replace("面板修改后自动保存，下次启动游戏时生效。","在工作台点击「保存设置」，下次启动游戏时生效。");
   text=entry.Replace(text,match=>{
    string value;
    string key=match.Groups[2].Value;
    if(!values.TryGetValue(key,out value))return match.Value;
    present.Add(key);
    return match.Groups[1].Value+key+match.Groups[3].Value+value+match.Groups[5].Value;
   });
   string newline=text.IndexOf('\n')>=0&&!text.Contains("\r\n")?"\n":"\r\n";
   foreach(var key in new[]{"Preset"}.Concat(keys)){
    if(present.Contains(key))continue;
    if(text.Length!=0&&!text.EndsWith("\n",StringComparison.Ordinal))text+=newline;
    text+=key+"="+values[key]+newline;
   }
   return Encoding.UTF8.GetBytes(text);
  }
 }

 public sealed partial class SettingsWindow {
  static readonly double[] weakWeights={1,1.5,2,3,4,6,10,25,100,1000};
  static readonly string[] aiPresetHelp={
   "恢复技能、机体性能和交战选项的基准值。停用整个模组请使用页首开关。",
   "将飞行员等级统一设为 5 级，其余技能、机体性能和交战选项使用基准值。",
   "高等级机动权重乘以 2，王牌专属机动权重最高提高到 2 倍，低等级机动权重除以 2。",
   "高等级机动权重乘以 3，王牌专属机动权重最高提高到 3 倍，低等级机动权重除以 3。",
   "高等级机动权重乘以 4，王牌专属机动权重最高提高到 4 倍，低等级机动权重除以 4。",
   "统一使用 5 级飞行员和王牌机动权重，提高机体性能，并开放热焰弹、规避和挑衅机动。"
  };
  static readonly string[] aiDifficulties={"所有难度","简单及以上","普通及以上","精英及以上","仅王牌难度"};

  void AcePilotsPage(){
   string name=AcePilotsSettings.FindInstalled(store.Root);
   if(name==null){
    Note("当前工作台没有安装合并版 Ace Pilots。");
    return;
   }

   var module=new DockPanel{Background=Brushes.Transparent};
   bool enabled=name==AcePilotsSettings.ModName;
   var moduleToggle=new CheckBox{Content=enabled?"已启用":"已停用",IsChecked=enabled,MinHeight=28,VerticalAlignment=VerticalAlignment.Center};
   AutomationProperties.SetName(moduleToggle,"启用敌方AI增强");
   AcePilotsHelp(module,moduleToggle,"决定下次启动游戏时是否加载敌方AI增强。切换后会立即保存启停状态。");
   moduleToggle.Checked+=async (s,e)=>await SetAcePilotsEnabled(name,true);
   moduleToggle.Unchecked+=async (s,e)=>await SetAcePilotsEnabled(name,false);
   DockPanel.SetDock(moduleToggle,Dock.Right);
   module.Children.Add(moduleToggle);
   var moduleLabel=Text("模组开关",14);
   moduleLabel.FontWeight=FontWeights.SemiBold;
   moduleLabel.VerticalAlignment=VerticalAlignment.Center;
   module.Children.Add(moduleLabel);
   body.Children.Add(new Border{Child=module,Background=Brush("#F5F9FB"),BorderBrush=Brush("#BED3DD"),
    BorderThickness=new Thickness(1),Padding=new Thickness(14,10,14,10),Margin=new Thickness(0,0,0,15)});

   body.Children.Add(Text("预设",14));
   var presetBar=new WrapPanel{Margin=new Thickness(0,7,0,3)};
   body.Children.Add(presetBar);
   var presets=new List<Button>();
   var updates=new List<Action>();
   Action updatePreset=()=>{
    int selected=AcePilotsSettings.PresetIndex(draft.AcePilots);
    for(int i=0;i<presets.Count;i++)presets[i].Tag=i==selected?"primary":null;
    bool custom=selected<0;
    presetBar.Children[presets.Count].Visibility=custom?Visibility.Visible:Visibility.Collapsed;
   };
   for(int i=0;i<AcePilotsSettings.PresetLabels.Length;i++){
    int index=i;
    var button=ActionButton(AcePilotsSettings.PresetLabels[i],()=>{
     AcePilotsSettings.ApplyPreset(draft.AcePilots,index);
     foreach(var update in updates)update();
     updatePreset();
     Changed();
    });
    button.MinWidth=65;
    button.Padding=new Thickness(12,6,12,6);
    AcePilotsHelp(button,button,aiPresetHelp[index]);
    presets.Add(button);
    presetBar.Children.Add(button);
   }
   var customLabel=Text("自定义",12,"#087F9F");
   customLabel.FontWeight=FontWeights.SemiBold;
   customLabel.VerticalAlignment=VerticalAlignment.Center;
   var customBadge=new Border{Child=customLabel,Background=Brush("#DCECF2"),BorderBrush=Brush("#A7C8D6"),
    BorderThickness=new Thickness(1),Padding=new Thickness(12,6,12,6),Margin=new Thickness(0,0,0,9)};
   AcePilotsHelp(customBadge,customBadge,"当前技能、机体性能或交战选项的组合与六个预设均不相同。");
   presetBar.Children.Add(customBadge);
   body.Children.Add(Text("预设调整技能、机体性能和交战选项。作用范围和脚本设置可单独调整。",12,"#496878"));
   updatePreset();

   Action changed=()=>{updatePreset();Changed();};
   var layout=new Grid{Margin=new Thickness(0,12,0,0)};
   layout.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
   layout.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
   layout.ColumnDefinitions.Add(new ColumnDefinition());
   layout.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(24)});
   layout.ColumnDefinitions.Add(new ColumnDefinition());
   var left=new StackPanel();
   var right=new StackPanel();
   layout.Children.Add(left);
   layout.Children.Add(right);
   Action arrange=()=>{
    bool wide=layout.ActualWidth>=730;
    layout.ColumnDefinitions[1].Width=new GridLength(wide?24:0);
    layout.ColumnDefinitions[2].Width=wide?new GridLength(1,GridUnitType.Star):new GridLength(0);
    Grid.SetRow(right,wide?0:1);
    Grid.SetColumn(right,wide?2:0);
   };
   layout.SizeChanged+=(s,e)=>{if(e.WidthChanged)arrange();};
   arrange();
   body.Children.Add(layout);

   var skills=AcePilotsGroup(left,"飞行员技术");
   AcePilotsSlider(skills,updates,changed,0,"飞行员等级",
    "统一飞行员等级。等级影响机动选择和机炮操作，5 级为王牌。「由游戏决定」会沿用任务分配的等级。",0,5,1,v=>v==0?"由游戏决定":Format(v)+" 级");
   AcePilotsSlider(skills,updates,changed,1,"高等级机动",
    "高等级机动是高等级飞行员更常选的动作。调高倍率会让这些动作更常被选中。×1 使用原版权重。",1,10,.5,v=>"×"+Format(v));
   AcePilotsSlider(skills,updates,changed,2,"王牌专属机动",
    "提高低等级飞行员不会采用的机动权重，例如急转规避和使用热焰弹。这里设定提高的上限。",1,20,1,v=>"×"+Format(v));
   AcePilotsSlider(skills,updates,changed,3,"低等级机动",
    "低等级机动是低等级飞行员更常选的动作。调大除数会降低这类动作的权重。设为「不采用」时，有更好的选择就会跳过这类动作。",0,weakWeights.Length-1,1,v=>v>=1000?"不采用":"÷"+Format(v),weakWeights);
   AcePilotsToggle(skills,updates,changed,4,"统一使用王牌机动权重",
    "机动选择统一按 5 级飞行员的权重计算，飞行员等级由上方的等级选项另行决定。");

   var performance=AcePilotsGroup(left,"机体性能");
   AcePilotsSlider(performance,updates,changed,5,"机动性能",
    "调整敌机的转向速度和加速度倍率。超过 2 倍时，敌机可能转向过头。",1,3,.1,v=>"×"+v.ToString("0.0##",CultureInfo.InvariantCulture));
   AcePilotsSlider(performance,updates,changed,6,"在空导弹上限",
    "限制每个敌人同时在空的导弹数量。原版每个敌人的上限为 2 枚。",2,8,1,v=>Format(v)+" 枚");
   AcePilotsSlider(performance,updates,changed,7,"过载耐受时间",
    "敌方在触发黑视并放缓转弯前，可以额外维持高过载转弯的秒数。",0,10,.5,v=>"+"+Format(v)+" 秒");

   var combat=AcePilotsGroup(right,"攻击与防御");
   AcePilotsToggle(combat,updates,changed,8,"取消攻击排队",
    "敌方有机会就能进攻，无需等待攻击轮次。可能同时有更多敌人攻击你。");
   var flares=AcePilotsToggle(combat,updates,changed,9,"允许使用热焰弹",
    "即使任务原本禁用，敌方也能使用热焰弹。合并版的敌机还可主动应对来袭导弹。");
   AcePilotsFlareLimit(combat,flares);
   AcePilotsToggle(combat,updates,changed,10,"允许规避",
    "即使任务原本限制规避，敌方也可执行规避机动。");
   AcePilotsToggle(combat,updates,changed,11,"允许挑衅机动",
    "允许敌方执行游戏内的挑衅机动。");

   var scope=AcePilotsGroup(right,"作用范围");
   AcePilotsSlider(scope,updates,changed,12,"机动调整起始难度",
    "从所选难度开始调整飞行员的机动权重。其余设置在各难度均可生效。",1,5,1,v=>aiDifficulties[(int)Math.Max(1,Math.Min(5,v))-1]);
   AcePilotsToggle(scope,updates,changed,13,"仅作用于飞机",
    "开启时仅调整飞机。关闭后，地面和海面单位的等级与交战选项也可受到影响。");
   AcePilotsToggle(scope,updates,changed,14,"包含友军",
    "把这些 AI 设置也应用到己方单位。具体单位类型仍由「仅作用于飞机」决定。");

   var scripts=AcePilotsGroup(right,"AI 行为脚本");
   AcePilotsSlider(scripts,updates,changed,15,"高难度脚本替换概率",
    "每种战斗机的各个行为槽按此概率换用更难的脚本。每分钟重新抽取，影响之后生成的敌机。",0,100,5,v=>Format(v)+"%");
   AcePilotsToggle(scripts,updates,changed,16,"包含未使用的脚本",
    "替换脚本时也会从战役机型从未使用的脚本中抽取。这些脚本与机型的组合未经过原作者测试。");
  }

  StackPanel AcePilotsGroup(StackPanel column,string name){
   var group=new StackPanel{Margin=new Thickness(0,0,0,14)};
   var heading=Text(name,15,"#087F9F");
   heading.FontWeight=FontWeights.SemiBold;
   group.Children.Add(new Border{Child=heading,BorderBrush=Brush("#BED3DD"),
    BorderThickness=new Thickness(0,0,0,1),Padding=new Thickness(0,0,0,6),Margin=new Thickness(0,0,0,4)});
   column.Children.Add(group);
   return group;
  }
  void AcePilotsHelp(FrameworkElement area,FrameworkElement control,string text){
   var content=Text(text,13);
   content.MaxWidth=320;
   area.ToolTip=new ToolTip{Content=content,FontFamily=Window.FontFamily,Background=Brush("#F8FBFC"),
    BorderBrush=Brush("#8EB7C9"),BorderThickness=new Thickness(1),Padding=new Thickness(10,7,10,7),
    Placement=PlacementMode.Top,VerticalOffset=-4};
   ToolTipService.SetInitialShowDelay(area,400);
   ToolTipService.SetShowDuration(area,16000);
   AutomationProperties.SetHelpText(control,text);
  }
  void AcePilotsSlider(StackPanel group,List<Action> updates,Action changed,int index,string name,string help,
   double min,double max,double step,Func<double,string> label,double[] choices=null){
   var row=new StackPanel{Background=Brushes.Transparent,Margin=new Thickness(0,3,0,3)};
   var heading=new DockPanel();
   var value=Text("",13,"#416574");value.FontWeight=FontWeights.SemiBold;
   DockPanel.SetDock(value,Dock.Right);heading.Children.Add(value);heading.Children.Add(Text(name,13));
   row.Children.Add(heading);
   var slider=new Slider{Minimum=min,Maximum=max,TickFrequency=step,SmallChange=step,LargeChange=step,
    IsMoveToPointEnabled=true,IsSnapToTickEnabled=true,MinHeight=24,Margin=new Thickness(0,1,0,0)};
   AutomationProperties.SetName(slider,name);
   AcePilotsHelp(row,slider,help);
   row.Children.Add(slider);group.Children.Add(row);
   bool updating=false;
   var update=new Action(()=>{
    double current=draft.AcePilots[index];
    updating=true;
    slider.Value=choices==null?current:Enumerable.Range(0,choices.Length).OrderBy(i=>Math.Abs(choices[i]-current)).First();
    value.Text=label(current);
    updating=false;
   });
   update();
   updates.Add(update);
   slider.ValueChanged+=(s,e)=>{
    if(updating)return;
    double current=choices==null?Math.Round(e.NewValue,6):choices[(int)Math.Round(e.NewValue)];
    draft.AcePilots[index]=current;
    value.Text=label(current);
    changed();
   };
  }
  CheckBox AcePilotsToggle(StackPanel group,List<Action> updates,Action changed,int index,string name,string help){
   var row=new DockPanel{Background=Brushes.Transparent,MinHeight=31,Margin=new Thickness(0,2,0,1)};
   var toggle=new CheckBox{MinHeight=30,VerticalAlignment=VerticalAlignment.Center};
   AutomationProperties.SetName(toggle,name);
   AcePilotsHelp(row,toggle,help);
   DockPanel.SetDock(toggle,Dock.Right);row.Children.Add(toggle);
   var label=Text(name,13);label.VerticalAlignment=VerticalAlignment.Center;row.Children.Add(label);
   group.Children.Add(row);
   bool updating=false;
   var update=new Action(()=>{
    updating=true;toggle.IsChecked=draft.AcePilots[index]!=0;updating=false;
   });
   update();
   updates.Add(update);
   RoutedEventHandler apply=(s,e)=>{
    if(updating)return;
    draft.AcePilots[index]=toggle.IsChecked==true?1:0;
    changed();
   };
   toggle.Checked+=apply;toggle.Unchecked+=apply;
   label.MouseLeftButtonUp+=(s,e)=>{toggle.Focus();toggle.IsChecked=toggle.IsChecked!=true;};
   return toggle;
  }

  void AcePilotsFlareLimit(StackPanel group,CheckBox flares){
   const int index=AcePilotsSettings.FlareLimitIndex;
   const string name="每架飞机累计上限";
   var row=new DockPanel{Background=Brushes.Transparent,Margin=new Thickness(12,0,0,6)};
   var unit=Text("次",12,"#496878");
   unit.Margin=new Thickness(7,0,0,0);
   unit.VerticalAlignment=VerticalAlignment.Center;
   DockPanel.SetDock(unit,Dock.Right);row.Children.Add(unit);
   var input=new TextBox{Text=Format(draft.AcePilots[index]),Width=105,Padding=new Thickness(6,4,6,4),
    FontSize=14,FontFamily=numbers,TextAlignment=TextAlignment.Center,VerticalAlignment=VerticalAlignment.Center};
   AutomationProperties.SetName(input,name+"数值");
   DockPanel.SetDock(input,Dock.Right);row.Children.Add(input);
   var caption=new StackPanel{Margin=new Thickness(0,0,8,0),VerticalAlignment=VerticalAlignment.Center};
   caption.Children.Add(Text(name,13));
   caption.Children.Add(Text("0 表示不限",11,"#496878"));
   row.Children.Add(caption);
   AcePilotsHelp(row,input,"每架飞机由 MOD 主动触发热焰弹的累计次数上限。原版模组默认为 9 次，0 表示不限。");

   Func<bool> commit=()=>{
    if(flares.IsChecked!=true)return true;
    int limit;
    bool valid=AcePilotsSettings.TryParseFlareLimit(input.Text,out limit);
    input.BorderBrush=Brush(valid?"#8EB7C9":"#AF3928");
    if(!valid){SetStatus("热焰弹上限请输入大于或等于 0 的整数。",true);return false;}
    draft.AcePilots[index]=limit;
    Changed();
    return true;
   };
   editors.Add(new Editor{Key="FlareMaxTotal",Input=input,Commit=commit});
   input.TextChanged+=(s,e)=>{if(!loading)commit();};
   input.KeyDown+=(s,e)=>{if(e.Key==System.Windows.Input.Key.Enter)commit();};
   Action show=()=>{
    bool enabled=flares.IsChecked==true;
    row.Visibility=enabled?Visibility.Visible:Visibility.Collapsed;
    if(!enabled){
     input.Text=Format(draft.AcePilots[index]);
     input.BorderBrush=Brush("#8EB7C9");
    }
   };
   show();
   flares.Checked+=(s,e)=>show();
   flares.Unchecked+=(s,e)=>show();
   group.Children.Add(row);
  }

  async Task SetAcePilotsEnabled(string name,bool enabled){
   if(busy||store==null)return;
   SetBusy(true);
   SetStatus(enabled?"正在启用敌方AI增强…":"正在停用敌方AI增强…");
   try{
    var request=new OperationRequest{Action=enabled?"ExtraEnable":"ExtraDisable",Root=store.Root,ExtraName=name};
    var result=await Task.Run(()=>Operations.Run(request,null));
    SetStatus(result.Message,!result.Success);
   }catch(Exception ex){SetStatus(ex.Message,true);}
   finally{
    SetBusy(false);
    ShowPage(page);
   }
  }
 }
}
