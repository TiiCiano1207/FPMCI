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
   Note("调整 HomingForesightAmount（提前量）。它不是命中率；0 也不会关闭导弹追踪。范围 0–1 为本工具的编辑限制，最多三位小数。");
   var mode=Text(missileMode=="none"?"当前为仅鼠标飞控：数值可以保存，但导弹模块未启用。":"当前方案："+(missileMode=="full"?"完整导弹强化 · 其他强化参数保持原样":"仅比例引导 · 保留其他原版导弹参数"),12,missileMode=="none"?"#087F9F":"#416574");
   mode.TextWrapping=TextWrapping.Wrap;mode.Margin=new Thickness(0,0,0,6);body.Children.Add(mode);
   Section("按导弹类型编辑","同类型的所有型号使用同一数值。若想减弱额外提前量，可以从原版值与 MOD 默认值的中间值试起。");
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
   controls.Children.Add(resets);Grid.SetColumn(controls,1);row.Children.Add(controls);
  }
 }
}
