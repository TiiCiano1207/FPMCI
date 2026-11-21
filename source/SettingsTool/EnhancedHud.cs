using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;

namespace AC8Settings {
 public sealed partial class SettingsWindow {
  const string HudName="AC8EnhancedHUD";
  static bool IsEnhancedHud(string name){
   return string.Equals(name.TrimStart('_'),HudName,StringComparison.OrdinalIgnoreCase);
  }
  string HudDirectory(){
   string library=System.IO.Path.Combine(store.Root,"ue4ss-mods");
   string on=System.IO.Path.Combine(library,HudName), off=System.IO.Path.Combine(library,"_"+HudName);
   if(Directory.Exists(on)&&Directory.Exists(off))throw new IOException("发现两份增强 HUD，请检查附加 MOD 库。");
   if(Directory.Exists(on))return on;
   if(Directory.Exists(off))return off;
   return System.IO.Path.Combine(store.Root,"optional-mods",HudName);
  }
  void HudOperation(string action,string token=null,string config=null){
   var result=Operations.Run(new OperationRequest{Root=store.Root,Action=action,ExtraToken=token,HudConfig=config},null);
   if(!result.Success)throw new IOException(result.Message);
   SetStatus(result.Message);
  }
  void EnhancedHudSection(){
   Section("增强 HUD","调整游戏仪表、目标框和机炮瞄准显示。开关会立即保存，下次启动游戏生效。");
   try{
    string directory=HudDirectory();
    bool enabled=Directory.Exists(System.IO.Path.Combine(store.Root,"ue4ss-mods",HudName));
    var row=Row("启用增强 HUD","启用仪表、目标框和机炮瞄准显示。");
    var toggle=new CheckBox{IsChecked=enabled,Content=enabled?"已开启":"已关闭",HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Center};
    Grid.SetColumn(toggle,1);row.Children.Add(toggle);
    const string key="ThirdPerson.CockpitHUD";
    Func<byte[]> read=()=>File.ReadAllBytes(Path.Combine(HudDirectory(),"config.ini"));
    Func<byte[],HudIni> parse=bytes=>new HudIni(Encoding.UTF8.GetString(bytes).TrimStart('\uFEFF'));
    var initial=parse(File.ReadAllBytes(Path.Combine(directory,"config.ini")));
    bool chase=new[]{"true","1","yes","on"}.Contains(initial.Get(key,"false"),StringComparer.OrdinalIgnoreCase);
    var childRow=Row("第三人称 HUD","在机外视角显示俯仰刻度、航向带和自动 EEGS 机炮瞄具。");
    childRow.Margin=new Thickness(18,0,0,0);
    var child=new CheckBox{IsChecked=chase,Content=chase?"已开启":"已关闭",HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Center};
    Grid.SetColumn(child,1);childRow.Children.Add(child);childRow.IsEnabled=enabled;
    child.Click+=(s,e)=>{
     try{
      byte[] bytes=read();var ini=parse(bytes);bool requested=child.IsChecked==true;
      ini.Set(key,requested?"true":"false");
      HudOperation("HudSave",ConfigStore.Hash(bytes),ini.ToString());chase=requested;
     }catch(Exception ex){child.IsChecked=chase;SetStatus(ex.Message,true);}
     child.Content=chase?"已开启":"已关闭";
    };
    toggle.Click+=(s,e)=>{
     try{HudOperation(toggle.IsChecked==true?"HudEnable":"HudDisable");enabled=toggle.IsChecked==true;}
     catch(Exception ex){toggle.IsChecked=enabled;SetStatus(ex.Message,true);}
     childRow.IsEnabled=enabled;toggle.Content=enabled?"已开启":"已关闭";
    };
   }catch(Exception ex){Note(ex.Message);}
  }
  // Keep comments, unrecognised fields and per-player additions when editing the INI.
  sealed class HudIni {
   readonly List<string> lines;
   readonly string newline;
   readonly Dictionary<string,int> indices=new Dictionary<string,int>();
   static readonly Regex assignment=new Regex(@"^(\s*\w+\s*=\s*)([^;#]*?)(\s*(?:[;#].*)?)$");
   public HudIni(string text){
    newline=text.Contains("\r\n")?"\r\n":"\n";
    lines=Regex.Split(text,"\r?\n").ToList();string section="";
    for(int i=0;i<lines.Count;i++){
     string line=lines[i];var heading=Regex.Match(line,@"^\s*\[\s*([^\]]+?)\s*\]\s*(?:[;#].*)?$");
     if(heading.Success){section=heading.Groups[1].Value;continue;}
     var match=assignment.Match(line);
     if(match.Success)indices[section+"."+match.Groups[1].Value.Split('=')[0].Trim()]=i;
    }
   }
   public string Get(string key,string fallback){
    int i;return indices.TryGetValue(key,out i)?assignment.Match(lines[i]).Groups[2].Value.Trim():fallback;
   }
   public void Set(string key,string value){
    int i;
    if(indices.TryGetValue(key,out i)){
     var m=assignment.Match(lines[i]);lines[i]=m.Groups[1].Value+value+m.Groups[3].Value;
    }else{
     var parts=key.Split('.');lines.Add("["+parts[0]+"]");indices[key]=lines.Count;lines.Add(parts[1]+" = "+value);
    }
   }
   public override string ToString(){return string.Join(newline,lines);}
  }
 }
}
