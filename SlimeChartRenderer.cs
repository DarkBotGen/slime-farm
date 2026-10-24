// Local-only PNG chart renderer. No webhook credentials or external services.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Net;
using System.Text;
using System.Web.Script.Serialization;

class SlimeChartRenderer {
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer {MaxJsonLength=300000};
    static readonly Color[] Colors={Color.FromArgb(245,133,194),Color.FromArgb(96,175,247),Color.FromArgb(148,219,100),Color.FromArgb(255,170,78)};
    static readonly string[] Names={"PINK","BLUE","GREEN","ORANGE"};
    static readonly double[] Prices={40000,1500,1500,10000};
    static double Num(object o) {try{return Math.Max(0,Convert.ToDouble(o));}catch{return 0;}}
    static double[] Numbers(object value) {var a=(System.Collections.IEnumerable)value;var l=new List<double>();foreach(var x in a)l.Add(Num(x));return l.ToArray();}
    static string Short(double n) {return n>=1e9?(n/1e9).ToString("0.00")+"B":n>=1e6?(n/1e6).ToString("0.00")+"M":n>=1000?(n/1000).ToString("0.0")+"K":n.ToString("0");}
    static string Clock(double seconds) {return new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc).AddSeconds(seconds).ToLocalTime().ToString("HH:mm");}
    static void Text(Graphics g,string text,float x,float y,float size,Color color,bool bold=false) {
        using(var f=new Font("Segoe UI",size,bold?FontStyle.Bold:FontStyle.Regular,GraphicsUnit.Pixel))
        using(var b=new SolidBrush(color)) g.DrawString(text,f,b,x,y);
    }
    static void Panel(Graphics g,Rectangle r) {using(var b=new SolidBrush(Color.FromArgb(29,31,36)))g.FillRectangle(b,r);}
    static void Plot(Graphics g,Rectangle panel,string title,double[] data,double start,double end,Color color) {
        Panel(g,panel);Text(g,title,panel.X+20,panel.Y+13,16,Color.FromArgb(224,227,233),true);
        var area=new Rectangle(panel.X+78,panel.Y+47,panel.Width-99,panel.Height-82);
        double max=1;foreach(double n in data)max=Math.Max(max,n);max*=1.15;
        using(var p=new Pen(Color.FromArgb(49,52,59))) {
            for(int i=0;i<=4;i++) {float y=area.Bottom-area.Height*i/4f;g.DrawLine(p,area.Left,y,area.Right,y);Text(g,Short(max*i/4),panel.X+10,y-8,11,Color.Gray);}
            for(int i=0;i<=4;i++) {float x=area.Left+area.Width*i/4f;g.DrawLine(p,x,area.Top,x,area.Bottom);Text(g,Clock(start+(end-start)*i/4),x-15,area.Bottom+10,11,Color.Gray);}
        }
        if(data.Length>0) {
            var points=new PointF[Math.Max(2,data.Length)];
            for(int i=0;i<points.Length;i++) {double v=data[Math.Min(i,data.Length-1)];points[i]=new PointF(area.Left+area.Width*i/(float)(points.Length-1),area.Bottom-(float)(area.Height*v/max));}
            var fill=new List<PointF>();fill.Add(new PointF(area.Left,area.Bottom));fill.AddRange(points);fill.Add(new PointF(area.Right,area.Bottom));
            using(var b=new SolidBrush(Color.FromArgb(47,color)))g.FillPolygon(b,fill.ToArray());
            using(var p=new Pen(color,2))g.DrawLines(p,points);
        }
    }
    static byte[] Render(Dictionary<string,object> input) {
        double[] rates=Numbers(input["rates"]);if(rates.Length!=4)throw new ArgumentException();
        double now=Num(input["timestamp"]),start=Num(input["start"]),duration=Math.Max(1,Math.Min(3600,now-start));
        var rows=new List<double[]>();foreach(object row in (System.Collections.IEnumerable)input["series"]) {var v=Numbers(row);if(v.Length!=4||rows.Count>=61)throw new ArgumentException();rows.Add(v);}
        var series=new double[4][];for(int i=0;i<4;i++){series[i]=new double[rows.Count];for(int j=0;j<rows.Count;j++)series[i][j]=rows[j][i];}
        var cash=new double[rows.Count];double money=0;for(int i=0;i<4;i++){money+=rates[i]*Prices[i];for(int j=0;j<rows.Count;j++)cash[j]+=series[i][j]*Prices[i];}
        using(var image=new Bitmap(1440,1040))using(var g=Graphics.FromImage(image)) {
            g.Clear(Color.FromArgb(17,19,23));g.SmoothingMode=SmoothingMode.AntiAlias;
            Text(g,"SLIME FARM",28,20,28,Color.White,true);
            Text(g,"Combined accounts  /  Live farming yields",28,58,15,Color.FromArgb(144,152,165));
            Text(g,Clock(now)+" local  |  updates every minute",1040,32,14,Color.FromArgb(144,152,165));
            Plot(g,new Rectangle(26,98,1000,240),"ESTIMATED SALE VALUE / HOUR",cash,start,now,Color.FromArgb(174,232,113));
            for(int i=0;i<4;i++)Plot(g,new Rectangle(26,352+i*152,1000,140),Names[i]+" GELS / HOUR",series[i],start,now,Colors[i]);
            Panel(g,new Rectangle(1044,98,370,240));Text(g,"ESTIMATED SALE VALUE",1066,120,17,Color.LightGray,true);
            Text(g,Short(money)+" / hour",1066,160,39,Color.FromArgb(174,232,113),true);
            Text(g,"At your supplied prices; no actual sales",1066,222,14,Color.Gray);
            Text(g,duration<3600?"Early session: rate extrapolated":"Rolling one-hour rate",1066,251,15,Color.LightGray);
            Text(g,Num(input["accounts"])+" active accounts  |  "+(duration/60).ToString("0.0")+" min observed",1066,283,15,Color.LightGray);
            for(int i=0;i<4;i++) {
                int y=352+i*152;Panel(g,new Rectangle(1044,y,370,140));
                Text(g,Names[i]+" GELS",1066,y+12,17,Colors[i],true);
                Text(g,Short(rates[i])+" / hour",1066,y+40,29,Color.White,true);
                Text(g,Short(rates[i]*Prices[i])+" coins / hour",1066,y+82,18,Colors[i]);
                Text(g,Short(Prices[i])+" per gel",1066,y+109,13,Color.Gray);
            }
            Text(g,"Chart: 1-minute yield samples scaled to hourly rates  |  Cards: combined rolling average  |  Transfers excluded",28,982,15,Color.FromArgb(144,152,165));
            Text(g,"Prices: pink 40,000  /  blue 1,500  /  green 1,500  /  orange 10,000 coins",28,1008,14,Color.Gray);
            using(var ms=new MemoryStream()){image.Save(ms,ImageFormat.Png);return ms.ToArray();}
        }
    }
    static void Main(string[] args) {
        if(args.Length==3&&args[0]=="--render") {File.WriteAllBytes(args[2],Render(Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(args[1]))));return;}
        bool created;using(var mutex=new System.Threading.Mutex(true,"Local\\SlimeChartRenderer17384",out created)) {
            if(!created)return;
            using(var listener=new HttpListener()) {
                listener.Prefixes.Add("http://127.0.0.1:17384/");listener.Start();
                while(true) {
                    var c=listener.GetContext();
                    try {
                        if(c.Request.Url.AbsolutePath!="/render"||c.Request.HttpMethod!="POST"||c.Request.ContentLength64<0||c.Request.ContentLength64>250000) {c.Response.StatusCode=400;continue;}
                        string body;using(var reader=new StreamReader(c.Request.InputStream,Encoding.UTF8))body=reader.ReadToEnd();
                        byte[] png=Render(Json.Deserialize<Dictionary<string,object>>(body));
                        byte[] response=Encoding.ASCII.GetBytes(Json.Serialize(new {png=Convert.ToBase64String(png)}));
                        c.Response.ContentType="application/json";c.Response.ContentLength64=response.Length;c.Response.OutputStream.Write(response,0,response.Length);
                    }catch {c.Response.StatusCode=400;}
                    finally {c.Response.Close();}
                }
            }
        }
    }
}
