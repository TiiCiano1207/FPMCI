using System;
using System.Linq;
using System.Globalization;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Automation;

namespace AC8Settings {
 public sealed class GuidanceSpec {
  public string Token,Label;public double Stock,Preset;public bool Difficulty;
  public string Key{get{return "guidance_"+Token;}}
  public GuidanceSpec(string token,string label,double stock,double preset,bool difficulty=false){Token=token;Label=label;Stock=stock;Preset=preset;Difficulty=difficulty;}
 }
 public static class Guidance {
  public static readonly GuidanceSpec[] Specs={
   new GuidanceSpec("MSL","MSL · 标准导弹",0,1),
   new GuidanceSpec("QAAM","QAAM · 高机动导弹",.4,1),
   new GuidanceSpec("SAAM","SAAM · 半主动导弹",.1,.95),
   new GuidanceSpec("2AAM","2AAM · 双目标导弹",0,.95),
   new GuidanceSpec("4AAM","4AAM · 四目标导弹",0,.9),
   new GuidanceSpec("6AAM","6AAM · 六目标导弹",0,.9),
   new GuidanceSpec("HCAA","HCAA · 高容量导弹",0,.8),
   new GuidanceSpec("HPAA","HPAA · 高威力导弹",0,.75),
   new GuidanceSpec("HVAA","HVAA · 高速导弹",0,.85),
   new GuidanceSpec("LAAM","LAAM · 远程导弹",0,.9),
   new GuidanceSpec("SASM","SASM · 小型空爆导弹",0,.9),
   new GuidanceSpec("STORY","C.STORY · 剧情难度",.2,1,true),
   new GuidanceSpec("EASY","EASY · 简单难度",.1,1,true)
  };
  // Campaign blueprint base damage, before parts and target damage rates.
  // AC8 Database, Steam build 26002268; see docs/VANILLA-FUSE-REFERENCE.json.
  public static readonly Dictionary<string,int> StockHitDamages=new Dictionary<string,int>{
   {"MSL",40},{"QAAM",80},{"SAAM",80},{"2AAM",60},{"4AAM",80},{"6AAM",80},{"HCAA",60},{"HPAA",160},{"HVAA",80},{"LAAM",80},{"SASM",50}};
  public static string StockHitDamage(string token){return StockHitDamages[token].ToString(CultureInfo.InvariantCulture);}
  public static readonly Rule[] FuseRules=Specs.Where(g=>!g.Difficulty).Select(g=>new Rule("fuse_"+g.Token,g.Label+"近炸增强",0,1,0,true)).ToArray();
  public static readonly Rule[] FuseParameterRules=Specs.Where(g=>!g.Difficulty).SelectMany(g=>new[]{
   new Rule("fuse_"+g.Token+"_TRIGGER",g.Token+" 触发距离",1,200,30),
   new Rule("fuse_"+g.Token+"_BLAST",g.Token+" 爆炸半径",1,500,50),
   new Rule("fuse_"+g.Token+"_DAMAGE",g.Token+" 范围伤害",1,500,30)}).ToArray();
  public static readonly Rule[] AllFuseRules=FuseRules.Concat(FuseParameterRules).ToArray();
  public static bool ValidFuse(Rule r,double v){return !double.IsNaN(v)&&!double.IsInfinity(v)&&v>=r.Min&&v<=r.Max&&(!r.Integer||v==Math.Floor(v))&&Math.Abs(v*1000-Math.Round(v*1000))<1e-8;}
  public static void ParseFuses(string text,ConfigState s){
   var seen=new HashSet<string>();
   foreach(var raw in text.Split('\n')){
    string line=raw.Trim();if(line.Length==0||line.StartsWith(";")||line.StartsWith("#"))continue;
    var m=Regex.Match(line,@"^([A-Z0-9_]+)\s*=\s*([0-9]+(?:\.[0-9]{1,3})?)$");
    string key=m.Success?"fuse_"+m.Groups[1].Value:"";
    var rule=AllFuseRules.FirstOrDefault(r=>r.Key==key);
    double v=m.Success?double.Parse(m.Groups[2].Value,CultureInfo.InvariantCulture):double.NaN;
    if(rule==null||!seen.Add(key)||!ValidFuse(rule,v))throw new FormatException("近炸配置未知、重复或超出范围："+line);
    s.Values[key]=v;
   }
   if(FuseRules.Any(r=>!seen.Contains(r.Key)))throw new FormatException("ProximityFuse.ini 需要全部 11 个弹种开关。");
  }
  public static readonly Rule[] Rules=Specs.Select(g=>new Rule(g.Key,g.Label,0,1,g.Preset)).ToArray();
  public static bool Valid(double v){return !double.IsNaN(v)&&!double.IsInfinity(v)&&v>=0&&v<=1&&Math.Abs(v*1000-Math.Round(v*1000))<1e-8;}
  public static void Validate(ConfigState s){foreach(var g in Specs){double v;if(!s.Values.TryGetValue(g.Key,out v)||!Valid(v))throw new FormatException(g.Label+"：请输入 0–1 之间的数值，最多三位小数。");}}
  public static void Parse(string text,ConfigState s){
   var seen=new HashSet<string>();
   foreach(var raw in text.Split('\n')){
    string line=raw.Trim();if(line.Length==0||line.StartsWith(";")||line.StartsWith("#"))continue;
    var m=Regex.Match(line,@"^([A-Z0-9]+)\s*=\s*([0-9]+(?:\.[0-9]{1,3})?)$");
    var g=m.Success?Specs.FirstOrDefault(x=>x.Token==m.Groups[1].Value):null;
    if(g==null||!seen.Add(g.Token))throw new FormatException("导弹引导配置未知、重复或格式无效："+line);
    s.Values[g.Key]=double.Parse(m.Groups[2].Value,CultureInfo.InvariantCulture);
   }
   if(seen.Count!=Specs.Length)throw new FormatException("MissileGuidance.ini 需要包含全部 13 个参数。");
  }
 }
 public sealed partial class SettingsWindow {
  void GuidancePage(){
   if(missileMode=="none")Note("当前为仅鼠标飞控：可以保存导弹设置，下次启用导弹模块时应用。");
   Section("原版 SASM 空爆参考","SASM 原版自带空爆：直击伤害 50、爆炸半径 50 米、范围伤害 30。");
   Note("直击参考为战役单枚基础伤害，未计零件和目标伤害倍率；MSL 在剧情难度下为 56。关闭近炸增强仍保留 SASM 的原版空爆。");
   Section("按导弹类型编辑","比例引导为提前量，0 不会关闭追踪。开启近炸后可独立编辑三项数值，保存后下次启动生效。");
   foreach(var g in Guidance.Specs.Where(x=>!x.Difficulty))GuidanceRow(g);
   var advanced=new Expander{Header="高级 · 难度参数",Foreground=Brush("#142F3C"),Margin=new Thickness(0,23,0,10),FontSize=15,IsExpanded=false};
   var advancedBody=new StackPanel();advanced.Content=advancedBody;body.Children.Add(advanced);
   var originalBody=body;body=advancedBody;
   Note("这两项来自难度数据表，与导弹型号参数分别保存；实际叠加效果需要游戏内测试。");
   foreach(var g in Guidance.Specs.Where(x=>x.Difficulty))GuidanceRow(g);
   body=originalBody;
  }
  void GuidanceRow(GuidanceSpec g){
   var row=Row(g.Label,"原版 "+Format(g.Stock)+"   ·   MOD 默认 "+Format(g.Preset)+"\n恢复原版值仅还原本参数，保留其他 MOD 功能。");
   var controls=new StackPanel{VerticalAlignment=VerticalAlignment.Center};
   var edit=new Grid();edit.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(38)});edit.ColumnDefinitions.Add(new ColumnDefinition());edit.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(38)});
   var input=new TextBox{Text=draft.Values[g.Key].ToString("0.000",CultureInfo.InvariantCulture),FontFamily=numbers,FontSize=16,HorizontalContentAlignment=HorizontalAlignment.Center,VerticalContentAlignment=VerticalAlignment.Center,MinHeight=39,Margin=new Thickness(7,0,7,0),ToolTip="0–1，最多三位小数；保存后下次启动生效"};
   AutomationProperties.SetName(input,g.Token+" 引导数值");
   bool valid=true;
   Func<bool> commit=()=>{
    // Detached controls may lose focus after a page rebuild; never replay stale text.
    if(loading||page!=8||!editors.Any(x=>object.ReferenceEquals(x.Input,input)))return true;
    double v;valid=Regex.IsMatch(input.Text.Trim(),@"^[0-9]+(?:\.[0-9]{1,3})?$")&&double.TryParse(input.Text.Trim(),NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out v);
    if(!valid||!double.TryParse(input.Text.Trim(),NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out v)||!Guidance.Valid(v)){
     valid=false;input.BorderBrush=Brush("#AF3928");save.IsEnabled=true;SetStatus(g.Label+"：请输入 0–1，最多三位小数。",true);return false;
    }
    input.ClearValue(TextBox.BorderBrushProperty);draft.Values[g.Key]=v;Changed();return true;
   };
   input.TextChanged+=(s,e)=>{if(!loading)commit();};
   input.LostKeyboardFocus+=(s,e)=>{if(commit())input.Text=draft.Values[g.Key].ToString("0.000",CultureInfo.InvariantCulture);};
   input.KeyDown+=(s,e)=>{if(e.Key==Key.Enter){commit();e.Handled=true;}};
   editors.Add(new Editor{Key=g.Key,Input=input,Commit=commit});
   foreach(int direction in new[]{-1,1}){
    int delta=direction;var step=new Button{Content=direction<0?"−":"+",Padding=new Thickness(0),MinHeight=39,ToolTip=direction<0?"减少 0.01":"增加 0.01"};
    AutomationProperties.SetName(step,g.Token+(direction<0?" 减少":" 增加"));
    step.Click+=(s,e)=>{double v;if(!double.TryParse(input.Text.Trim(),NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out v)||!Guidance.Valid(v)){commit();return;}input.Text=Math.Max(0,Math.Min(1,Math.Round(v+delta*.01,3))).ToString("0.000",CultureInfo.InvariantCulture);};
    Grid.SetColumn(step,direction<0?0:2);edit.Children.Add(step);
   }
   Grid.SetColumn(input,1);edit.Children.Add(input);controls.Children.Add(edit);
   var resets=new WrapPanel{Margin=new Thickness(0,7,0,0)};
   foreach(bool stock in new[]{true,false}){
    bool original=stock;var b=new Button{Content=stock?"恢复原版值":"恢复 MOD 默认值",FontSize=11,Padding=new Thickness(8,5,8,5),Margin=new Thickness(0,0,7,3)};
    AutomationProperties.SetName(b,g.Token+(stock?" 恢复原版值":" 恢复 MOD 默认值"));
    b.Click+=(s,e)=>{input.Text=(original?g.Stock:g.Preset).ToString("0.000",CultureInfo.InvariantCulture);commit();};resets.Children.Add(b);
   }
   controls.Children.Add(resets);
   if(!g.Difficulty){
    string key="fuse_"+g.Token;
    var toggle=new CheckBox{IsChecked=draft.Values[key]==1,Content=draft.Values[key]==1?"近炸增强 · 已开启":"近炸增强 · 原版",Margin=new Thickness(0,9,0,0),HorizontalAlignment=HorizontalAlignment.Right};
    AutomationProperties.SetName(toggle,g.Token+" 近炸增强");
    var parameters=new StackPanel{Margin=new Thickness(0,8,0,0),Visibility=toggle.IsChecked==true?Visibility.Visible:Visibility.Collapsed};
    var fields=new List<TextBox>();
    foreach(string suffix in new[]{"TRIGGER","BLAST","DAMAGE"}){
     var rule=Guidance.FuseParameterRules.Single(r=>r.Key==key+"_"+suffix);
     string label=suffix=="TRIGGER"?"触发距离（米）":suffix=="BLAST"?"爆炸半径（米）":"范围伤害";
     var line=new Grid{Margin=new Thickness(0,3,0,3)};line.ColumnDefinitions.Add(new ColumnDefinition());line.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(104)});
     var caption=Text(label,12,"#496878");
     if(suffix=="DAMAGE"){
      caption.Inlines.Add(new System.Windows.Documents.Run("（原版直击："+Guidance.StockHitDamage(g.Token)+"）"){FontSize=11});
      caption.ToolTip="来源：AC8 数据库（Steam 26002268）。战役单枚基础直击伤害，未计零件和目标伤害倍率；与可编辑的范围伤害是不同参数。"+(g.Token=="MSL"?"剧情难度下 MSL 直击伤害为 56。":"");
     }
     caption.VerticalAlignment=VerticalAlignment.Center;line.Children.Add(caption);
     var field=new TextBox{Text=draft.Values[rule.Key].ToString("0.###",CultureInfo.InvariantCulture),FontFamily=numbers,FontSize=16,HorizontalContentAlignment=HorizontalAlignment.Center,ToolTip=rule.Min+"–"+rule.Max+"，最多三位小数"};
     AutomationProperties.SetName(field,g.Token+" "+label);
     Func<bool> commitField=()=>{
      if(loading||page!=8||draft.Values[key]==0||!editors.Any(x=>object.ReferenceEquals(x.Input,field)))return true;
      double v;
      if(!Regex.IsMatch(field.Text.Trim(),@"^[0-9]+(?:\.[0-9]{1,3})?$")||!double.TryParse(field.Text.Trim(),NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out v)||!Guidance.ValidFuse(rule,v)){
       field.BorderBrush=Brush("#AF3928");save.IsEnabled=true;SetStatus(rule.Label+"：请输入 "+rule.Min+"–"+rule.Max+"，最多三位小数。",true);return false;
      }
      field.ClearValue(TextBox.BorderBrushProperty);draft.Values[rule.Key]=v;Changed();return true;
     };
     field.TextChanged+=(s,e)=>{if(!loading)commitField();};field.LostKeyboardFocus+=(s,e)=>commitField();
     editors.Add(new Editor{Key=rule.Key,Input=field,Commit=commitField});fields.Add(field);
     Grid.SetColumn(field,1);line.Children.Add(field);parameters.Children.Add(line);
    }
    var hint=Text("爆炸半径小于触发距离时，目标可能处于杀伤范围外。",11,"#496878");hint.TextWrapping=TextWrapping.Wrap;hint.Margin=new Thickness(0,5,0,0);parameters.Children.Add(hint);
    var reset=new Button{Content="恢复近炸默认",FontSize=11,Padding=new Thickness(8,5,8,5),HorizontalAlignment=HorizontalAlignment.Right,Margin=new Thickness(0,7,0,0)};
    reset.Click+=(s,e)=>{foreach(var field in fields){var editor=editors.Single(x=>object.ReferenceEquals(x.Input,field));field.Text=Guidance.FuseParameterRules.Single(r=>r.Key==editor.Key).Default.ToString("0.###",CultureInfo.InvariantCulture);}};
    parameters.Children.Add(reset);
    RoutedEventHandler changed=(s,e)=>{
     if(loading)return;draft.Values[key]=toggle.IsChecked==true?1:0;toggle.Content=toggle.IsChecked==true?"近炸增强 · 已开启":"近炸增强 · 原版";
     if(toggle.IsChecked!=true)foreach(var field in fields){field.ClearValue(TextBox.BorderBrushProperty);field.Text=draft.Values[editors.Single(x=>object.ReferenceEquals(x.Input,field)).Key].ToString("0.###",CultureInfo.InvariantCulture);}
     parameters.Visibility=toggle.IsChecked==true?Visibility.Visible:Visibility.Collapsed;Changed();
     if(toggle.IsChecked==true)Window.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded,new Action(()=>parameters.BringIntoView()));
    };
    toggle.Checked+=changed;toggle.Unchecked+=changed;controls.Children.Add(toggle);controls.Children.Add(parameters);
   }
   Grid.SetColumn(controls,1);row.Children.Add(controls);
  }
 }
}
