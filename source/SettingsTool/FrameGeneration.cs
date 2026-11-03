using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace AC8Settings {
 public static class FrameGeneration {
  const string Plugin="r.Streamline.InitializePlugin", Enable="r.Streamline.DLSSG.Enable";
  public static bool Parse(string text){
   if(text.Length==0)return false;
   var values=new Dictionary<string,string>();bool section=false;
   foreach(string raw in text.TrimStart('\uFEFF').Split('\n')){
    string line=raw.Trim();if(line.Length==0||line.StartsWith(";")||line.StartsWith("#"))continue;
    if(line=="[ConsoleVariables]"){if(section)throw new FormatException("帧生成配置含重复分区。");section=true;continue;}
    var m=Regex.Match(line,@"^([^=]+?)\s*=\s*([01])$");
    string key=m.Success?m.Groups[1].Value.Trim():"";
    if(!section||!m.Success||(key!=Plugin&&key!=Enable)||values.ContainsKey(key))throw new FormatException("帧生成配置无效："+line);
    values[key]=m.Groups[2].Value;
   }
   if(values.Count!=2)throw new FormatException("帧生成配置不完整，请重新读取或恢复备份。");
   return values[Enable]=="1";
  }
  public static string Serialize(string text,bool enabled){
   if(text.Length==0)text="; DLSS Frame Generation startup settings only.\r\n[ConsoleVariables]\r\n"+Plugin+"=1\r\n"+Enable+"=0\r\n";
   text=Replace(text,Enable,enabled?"1":"0");
   return enabled?Replace(text,Plugin,"1"):text;
  }
  static string Replace(string text,string key,string value){
   return Regex.Replace(text,@"(?m)^([\t ]*"+Regex.Escape(key)+@"[\t ]*=[\t ]*)[01]",m=>m.Groups[1].Value+value);
  }
 }
}
