using System;
using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Globalization;
using System.Threading;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.ComponentModel;

class Pet : Form {
 double food=80, mood=80, energy=80, phase=0, pause=0, saved=0;
 bool sleeping=false, roam=true, dragging=false, moved=false;
 int direction=1; Point grab, origin; string message="你好，我是 Anny！", name="Anny", assetStatus="使用内置边牧占位动画";
 string statePath; Image sheet; Dictionary<string,string> cfg=new Dictionary<string,string>();
 int cols=8, rows=9, fps=8; NotifyIcon tray; System.Windows.Forms.Timer timer;
 DateTime last=DateTime.UtcNow; Random random=new Random();
 bool test; int testLook=-1;
 bool panelVisible=false; double hoverGrace=0;
 readonly Rectangle dogZone=new Rectangle(54,160,192,208);
 readonly Rectangle panelZone=new Rectangle(8,8,284,144);
 Rectangle QuickButton(int i){return new Rectangle(20+i*88,111,80,28);}
 void HoverStep(Point local,double dt){bool near=dogZone.Contains(local)||(panelVisible&&new Rectangle(8,8,284,360).Contains(local));if(near||dragging||menuOpen){panelVisible=true;hoverGrace=.4;}else{hoverGrace=Math.Max(0,hoverGrace-dt);if(hoverGrace<=0)panelVisible=false;}}
 void QuickAction(int i){if(i==0)Feed();else if(i==1)Play();else{sleeping=!sleeping;activityLeft=0;animationTime=0;Say(sleeping?"晚安 z Z":"睡醒啦！");}}
 static Color Ink=Color.FromArgb(25,23,49), Cyan=Color.FromArgb(23,232,243), Yellow=Color.FromArgb(255,218,51), Pink=Color.FromArgb(255,79,139), Mint=Color.FromArgb(64,239,173);
 void Box(Graphics g,Rectangle rect,Color fill){using(Brush b=new SolidBrush(fill))g.FillRectangle(b,rect);using(Pen pen=new Pen(Ink,2))g.DrawRectangle(pen,rect);}
 void DrawPanel(Graphics g){
  g.SmoothingMode=SmoothingMode.None;using(Brush shadow=new SolidBrush(Ink))g.FillRectangle(shadow,14,14,280,142);
  Box(g,new Rectangle(8,8,280,140),Color.FromArgb(255,253,238));Box(g,new Rectangle(8,8,280,42),Cyan);
  using(Brush ink=new SolidBrush(Ink))using(Font title=new Font("Consolas",20,FontStyle.Bold))using(Font small=new Font("Microsoft YaHei UI",8.5f))using(Font label=new Font("Microsoft YaHei UI",9,FontStyle.Bold)){
   g.FillRectangle(ink,22,24,7,7);g.FillRectangle(ink,32,19,7,7);g.FillRectangle(ink,42,24,7,7);g.FillRectangle(ink,29,33,14,8);
   g.DrawString(name,title,ink,59,13);g.DrawString("右键 · 更多",small,ink,207,24);
   string[] labels={"饱食","心情","精力"};double[] values={food,mood,energy};Color[] colors={Yellow,Pink,Mint};
   for(int i=0;i<3;i++){int x=20+i*88;g.DrawString(labels[i],label,ink,x,59);string value=((int)Math.Round(values[i])).ToString();g.DrawString(value,small,ink,x+53,61);Box(g,new Rectangle(x,83,76,14),Color.White);int blocks=(int)Math.Round(values[i]/10);using(Brush b=new SolidBrush(colors[i]))for(int j=0;j<blocks;j++)g.FillRectangle(b,x+3+j*7,86,5,8);}
   string[] buttons={"喂食","摸摸",sleeping?"唤醒":"睡觉"};Point mouse=PointToClient(Cursor.Position);
   for(int i=0;i<3;i++){Rectangle rect=QuickButton(i);Color fill=i==0?Yellow:i==1?Pink:Mint;if(!test&&rect.Contains(mouse))fill=Cyan;Box(g,rect,fill);SizeF size=g.MeasureString(buttons[i],label);g.DrawString(buttons[i],label,ink,rect.X+(rect.Width-size.Width)/2,rect.Y+5);}
  }
  g.SmoothingMode=SmoothingMode.AntiAlias;
 }

 bool trackMouse=true, blend=false, moving=true;
 string activity="", renderedAction=""; double activityLeft=0, animationTime=0, wanderLeft=5, motionRemainder=0;
 bool menuOpen=false; int lookIndex=0;
 double Rate(string action){return Math.Max(1,Math.Min(24,Number(action+"Fps",fps)));}
 int Count(string action){return Math.Max(1,Math.Min(cols,Number(action+"Frames",cols)));}
 static int LookDirection(double dx,double dy){double angle=Math.Atan2(dx,-dy)*180/Math.PI;if(angle<0)angle+=360;return ((int)Math.Round(angle/22.5))%16;}
 void Begin(string action,string text,int loops=1){sleeping=false;activity=action;activityLeft=Count(action)/Rate(action)*loops;animationTime=0;renderedAction=action;Say(text);pause=activityLeft;}
 string ActionName(){if(test&&testLook>=0){lookIndex=testLook;return "look";}if(sleeping)return "sleep";if(activityLeft>0)return activity;if(dragging)return "wave";if(roam&&moving&&!menuOpen&&!panelVisible&&pause<=0)return direction>0?"walkRight":"walkLeft";
  Point mouse=Cursor.Position;double dx=mouse.X-(Left+Width/2),dy=mouse.Y-(Top+245);double distance=Math.Sqrt(dx*dx+dy*dy);
  if(trackMouse&&!menuOpen&&distance>30&&distance<500&&rows>=11){lookIndex=LookDirection(dx,dy);return "look";}return food<20?"wait":"idle";}
 Dictionary<string,Rectangle> opaqueBounds=new Dictionary<string,Rectangle>();
 Rectangle FrameBounds(int column,int row,int cw,int ch){
  string key=column+":"+row;Rectangle cached;if(opaqueBounds.TryGetValue(key,out cached))return cached;
  int left=cw,top=ch,right=-1,bottom=-1;Bitmap bitmap=(Bitmap)sheet;
  for(int y=0;y<ch;y++)for(int x=0;x<cw;x++)if(bitmap.GetPixel(column*cw+x,row*ch+y).A>=128){left=Math.Min(left,x);right=Math.Max(right,x);top=Math.Min(top,y);bottom=Math.Max(bottom,y);}
  cached=right<left?new Rectangle(0,0,cw,ch):Rectangle.FromLTRB(left,top,right+1,bottom+1);opaqueBounds[key]=cached;return cached;
 }
 RectangleF SpriteDestination(string action,int frame,int row,int cw,int ch,float scale){
  RectangleF dst=new RectangleF((Width-cw*scale)/2,160+(208-ch*scale)/2,cw*scale,ch*scale);
  if(action=="sleep"){
   Rectangle rest=FrameBounds(0,Number("idle",0),cw,ch), current=FrameBounds(frame,row,cw,ch);
   dst.Offset(((rest.Left+rest.Right-current.Left-current.Right)/2f)*scale,(rest.Bottom-current.Bottom)*scale);
  }
  return dst;
 }
 void DrawSprite(Graphics g,RectangleF dst,RectangleF src,float opacity){using(ImageAttributes attr=new ImageAttributes()){ColorMatrix matrix=new ColorMatrix();matrix.Matrix33=opacity;attr.SetColorMatrix(matrix);g.DrawImage(sheet,Rectangle.Round(dst),src.X,src.Y,src.Width,src.Height,GraphicsUnit.Pixel,attr);}}

 public Pet(bool testing) {
  test=testing; statePath= testing ? Path.Combine(Path.GetTempPath(),"Anny-test-"+Guid.NewGuid()+".txt") : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"AnnyDesktop","state.txt");
  FormBorderStyle=FormBorderStyle.None; ShowInTaskbar=false; TopMost=true; ClientSize=new Size(300,380);
  BackColor=Color.Black; DoubleBuffered=false; StartPosition=FormStartPosition.Manual;
  Rectangle area=Screen.PrimaryScreen.WorkingArea; Location=new Point(area.Right-340,area.Bottom-400);
  LoadAssets(); LoadState();
  ContextMenuStrip menu=new ContextMenuStrip(); menu.BackColor=Color.FromArgb(255,253,238);menu.ForeColor=Ink;menu.Font=new Font("Microsoft YaHei UI",10);
  menu.Items.Add("喂食 🍖",null,delegate{ Feed(); });
  menu.Items.Add("摸头 / 玩耍",null,delegate{ Play(); });
  menu.Items.Add("挥爪打招呼",null,delegate{Begin("wave","嗨！我在这里 ♥");});
  menu.Items.Add("跳一下",null,delegate{Begin("jump","接住我的开心！");});
  menu.Items.Add("受挫 / 安慰",null,delegate{Begin("sad","抱抱我就好啦");});
  menu.Items.Add("等你回来",null,delegate{Begin("wait","我乖乖等你");});
  menu.Items.Add("认真思考",null,delegate{Begin("think","让我想一想…");});
  menu.Items.Add("好奇观察",null,delegate{Begin("review","这是什么呀？");});
  menu.Items.Add("睡觉 / 唤醒",null,delegate{sleeping=!sleeping;activityLeft=0;animationTime=0;Say(sleeping?"晚安 z Z":"睡醒啦！");});
  ToolStripMenuItem gaze=new ToolStripMenuItem("休息时看鼠标");gaze.Checked=true;gaze.CheckOnClick=true;gaze.CheckedChanged+=delegate{trackMouse=gaze.Checked;};menu.Items.Add(gaze);
  ToolStripMenuItem smooth=new ToolStripMenuItem("帧间柔化（可能有重影）");smooth.CheckOnClick=true;smooth.CheckedChanged+=delegate{blend=smooth.Checked;};menu.Items.Add(smooth);
  menu.Opened+=delegate{menuOpen=true;};menu.Closed+=delegate{menuOpen=false;};
  ToolStripMenuItem walk=new ToolStripMenuItem("自由走动"); walk.Checked=true; walk.CheckOnClick=true; walk.CheckedChanged+=delegate{roam=walk.Checked;moving=roam;wanderLeft=4;}; menu.Items.Add(walk);
  ToolStripMenuItem top=new ToolStripMenuItem("保持置顶"); top.Checked=true; top.CheckOnClick=true; top.CheckedChanged+=delegate{TopMost=top.Checked;}; menu.Items.Add(top);
  menu.Items.Add("关于 / 素材状态",null,delegate{MessageBox.Show(name+" 独立桌宠 4.0\n平时只显示 Anny；悬停显示像素互动面板。\n左键拖动，单击摸头，右键操作。\n"+assetStatus+"\n素材位于程序旁 assets 目录，替换后重启。\n饱食、心情、精力保存在本机，无网络连接。\n约 60Hz 刷新；原画每动作 4～8 帧。", "Anny Desktop");});
  menu.Items.Add("退出",null,delegate{Close();}); ContextMenuStrip=menu;
  if(!test){ tray=new NotifyIcon(); tray.Icon=SystemIcons.Application; tray.Text="Anny 桌宠 · 右键互动"; tray.ContextMenuStrip=menu; tray.Visible=true; tray.DoubleClick+=delegate{Show(); Location=new Point(Screen.PrimaryScreen.WorkingArea.Right-340,Screen.PrimaryScreen.WorkingArea.Bottom-400);}; }
  MouseDown+=delegate(object s,MouseEventArgs e){if(e.Button==MouseButtons.Left){if(panelVisible&&panelZone.Contains(e.Location)){for(int i=0;i<3;i++)if(QuickButton(i).Contains(e.Location)){QuickAction(i);break;}return;}dragging=true;moved=false;grab=Cursor.Position;origin=Location;Capture=true;}};
  MouseMove+=delegate{if(dragging){Point p=Cursor.Position; int dx=p.X-grab.X,dy=p.Y-grab.Y;if(Math.Abs(dx)+Math.Abs(dy)>4)moved=true;Location=new Point(origin.X+dx,origin.Y+dy);}};
  MouseUp+=delegate(object s,MouseEventArgs e){if(dragging){dragging=false;Capture=false;Clamp();if(!moved)Play();}};
  MouseCaptureChanged+=delegate{if(!Capture)dragging=false;};
  timer=new System.Windows.Forms.Timer();timer.Interval=16;timer.Tick+=delegate{TickPet();};if(!test)timer.Start();
  FormClosed+=delegate{timer.Stop();if(!test)SaveState();if(tray!=null)tray.Dispose();if(sheet!=null)sheet.Dispose();};
 }
 static double Limit(double v){return Math.Max(0,Math.Min(100,v));}
 void Say(string s){message=s;pause=3;RenderLayer();}
 void Feed(){food=Limit(food+22);mood=Limit(mood+5);Begin("eat","好吃！谢谢你 ♥",4);}
 void Play(){sleeping=false;mood=Limit(mood+12);energy=Limit(energy-3);Begin("wave","喜欢和你一起玩 ♥");}
 void TickPet(){DateTime now=DateTime.UtcNow;double dt=Math.Min(.2,Math.Max(0,(now-last).TotalSeconds));last=now;Step(dt);}
 void Step(double dt){if(!test)HoverStep(PointToClient(Cursor.Position),dt);phase+=dt;pause=Math.Max(0,pause-dt);saved+=dt;
  food=Limit(food-dt*.022);mood=Limit(mood-dt*.012);energy=Limit(energy+dt*(sleeping?.35:-.012));
  if(!dragging&&!menuOpen){activityLeft=Math.Max(0,activityLeft-dt);animationTime+=dt;}
  if(roam&&!sleeping&&!dragging&&!menuOpen&&!panelVisible&&activityLeft<=0&&pause<=0){wanderLeft-=dt;if(wanderLeft<=0){moving=!moving;wanderLeft=moving?3+random.Next(5):3+random.Next(4);if(moving)direction=random.Next(2)==0?-1:1;}
   if(moving){motionRemainder+=direction*Math.Max(10,Math.Min(120,Number("speed",48)))*dt;int delta=(int)motionRemainder;motionRemainder-=delta;Left+=delta;Rectangle a=Screen.FromControl(this).WorkingArea;if(Left<a.Left||Right>a.Right){direction=-direction;motionRemainder=0;Clamp();}}}
  if(saved>30){saved=0;SaveState();}RenderLayer();
 }
 void Clamp(){Rectangle a=Screen.FromControl(this).WorkingArea;Left=Math.Max(a.Left,Math.Min(Left,a.Right-Width));Top=Math.Max(a.Top,Math.Min(Top,a.Bottom-Height));}
 void SaveState(){try{Directory.CreateDirectory(Path.GetDirectoryName(statePath));string value=food.ToString(CultureInfo.InvariantCulture)+"\n"+mood.ToString(CultureInfo.InvariantCulture)+"\n"+energy.ToString(CultureInfo.InvariantCulture)+"\n"+DateTime.UtcNow.Ticks;File.WriteAllText(statePath+".tmp",value);if(File.Exists(statePath))File.Replace(statePath+".tmp",statePath,null);else File.Move(statePath+".tmp",statePath);}catch{}}
 void LoadState(){try{string[] a=File.ReadAllLines(statePath);double f=double.Parse(a[0],CultureInfo.InvariantCulture),m=double.Parse(a[1],CultureInfo.InvariantCulture),e=double.Parse(a[2],CultureInfo.InvariantCulture);if(double.IsNaN(f+m+e)||double.IsInfinity(f+m+e))return;double elapsed=Math.Max(0,Math.Min(28800,(DateTime.UtcNow-new DateTime(long.Parse(a[3]),DateTimeKind.Utc)).TotalSeconds));food=Limit(f-elapsed*.001);mood=Limit(m-elapsed*.0005);energy=Limit(e);}catch{}}
 int Number(string key,int fallback){int n;return cfg.ContainsKey(key)&&int.TryParse(cfg[key],out n)?n:fallback;}
 void LoadAssets(){try{string root=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"assets");string ini=Path.Combine(root,"pet.ini");if(!File.Exists(ini))return;foreach(string line in File.ReadAllLines(ini)){int eq=line.IndexOf('=');if(eq>0&&!line.TrimStart().StartsWith("#"))cfg[line.Substring(0,eq).Trim()]=line.Substring(eq+1).Trim();}if(cfg.ContainsKey("name"))name=cfg["name"];
  cols=Number("columns",8);rows=Number("rows",9);fps=Number("fps",8);if(cols<1||cols>64||rows<1||rows>64||fps<1||fps>60)throw new Exception("网格或帧率无效");
  string file=Path.Combine(root,cfg.ContainsKey("image")?cfg["image"]:"pet.png");if(!File.Exists(file))return;
  using(Image img=Image.FromFile(file)){if(img.Width%cols!=0||img.Height%rows!=0)throw new Exception("图片尺寸必须能整除网格");sheet=new Bitmap(img);}assetStatus="已加载素材："+Path.GetFileName(file);
 }catch(Exception ex){if(sheet!=null){sheet.Dispose();sheet=null;}assetStatus="素材加载失败，已使用占位形象："+ex.Message;}}
 protected override CreateParams CreateParams { get {CreateParams p=base.CreateParams;p.ExStyle|=0x80000;return p;} }
 [StructLayout(LayoutKind.Sequential)] struct NativePoint{public int X,Y;public NativePoint(int x,int y){X=x;Y=y;}}
 [StructLayout(LayoutKind.Sequential)] struct NativeSize{public int Width,Height;public NativeSize(int w,int h){Width=w;Height=h;}}
 [StructLayout(LayoutKind.Sequential,Pack=1)] struct BlendFunction{public byte Operation,Flags,Alpha,Format;}
 [DllImport("user32.dll",SetLastError=true)] static extern bool UpdateLayeredWindow(IntPtr hwnd,IntPtr dst,ref NativePoint pos,ref NativeSize size,IntPtr src,ref NativePoint source,uint key,ref BlendFunction blend,uint flags);
 [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
 [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd,IntPtr dc);
 [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
 [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
 [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc,IntPtr obj);
 [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
 Bitmap RenderFrame(){Bitmap b=new Bitmap(Width,Height,PixelFormat.Format32bppPArgb);using(Graphics g=Graphics.FromImage(b)){g.Clear(Color.Transparent);g.SmoothingMode=SmoothingMode.AntiAlias;g.TextRenderingHint=System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;g.InterpolationMode=InterpolationMode.HighQualityBicubic;DrawScene(g);}return b;}
 void Present(Bitmap frame){IntPtr screen=GetDC(IntPtr.Zero),memory=IntPtr.Zero,bmp=IntPtr.Zero,old=IntPtr.Zero;try{
  memory=CreateCompatibleDC(screen);bmp=frame.GetHbitmap(Color.FromArgb(0));old=SelectObject(memory,bmp);
  NativePoint pos=new NativePoint(Left,Top),source=new NativePoint(0,0);NativeSize size=new NativeSize(Width,Height);BlendFunction blendFunction=new BlendFunction{Operation=0,Flags=0,Alpha=255,Format=1};
  if(!UpdateLayeredWindow(Handle,screen,ref pos,ref size,memory,ref source,0,ref blendFunction,2))throw new Win32Exception(Marshal.GetLastWin32Error());
 }finally{if(old!=IntPtr.Zero)SelectObject(memory,old);if(bmp!=IntPtr.Zero)DeleteObject(bmp);if(memory!=IntPtr.Zero)DeleteDC(memory);if(screen!=IntPtr.Zero)ReleaseDC(IntPtr.Zero,screen);}}
 void RenderLayer(){if(test||IsDisposed||!IsHandleCreated)return;using(Bitmap frame=RenderFrame())Present(frame);}
 protected override void OnShown(EventArgs e){base.OnShown(e);RenderLayer();}
 protected override void OnPaintBackground(PaintEventArgs e){}
 protected override void OnPaint(PaintEventArgs e){RenderLayer();}
 void DrawScene(Graphics g){
  string action=ActionName();if(action!=renderedAction){renderedAction=action;animationTime=0;}
  if(sheet!=null){int row=action=="look"?9+lookIndex/8:Math.Max(0,Math.Min(rows-1,Number(action,0)));int count=Count(action);double position=animationTime*Rate(action);int frame=action=="look"?lookIndex%8:(int)position%count;
   int cw=sheet.Width/cols,ch=sheet.Height/rows;float scale=Math.Min(192f/cw,208f/ch);RectangleF dst=SpriteDestination(action,frame,row,cw,ch,scale);
   RectangleF source=new RectangleF(frame*cw,row*ch,cw,ch);DrawSprite(g,dst,source,1);
   if(blend&&action!="look"){float mix=(float)(position-Math.Floor(position));if(mix>.65f)DrawSprite(g,SpriteDestination(action,(frame+1)%count,row,cw,ch,scale),new RectangleF(((frame+1)%count)*cw,row*ch,cw,ch),(mix-.65f)/.35f*.65f);}
  }
  else DrawDog(g);
  if(panelVisible)DrawPanel(g);
 }

 void Bar(Graphics g,int x,int y,double value,Color color){g.FillRectangle(Brushes.LightGray,x,y,52,5);using(Brush b=new SolidBrush(color))g.FillRectangle(b,x,y,(float)(52*value/100),5);}
 void DrawDog(Graphics g){float bob=sleeping?3:(float)Math.Sin(phase*5)*2;g.TranslateTransform(0,bob);Color ink=Color.FromArgb(35,40,48);using(Brush black=new SolidBrush(ink))using(Pen outline=new Pen(ink,3)){
  float wag=(float)Math.Sin(phase*9)*12;using(Pen tail=new Pen(ink,18)){tail.StartCap=LineCap.Round;tail.EndCap=LineCap.Round;g.DrawBezier(tail,new PointF(154,159),new PointF(193,160),new PointF(202,128+wag),new PointF(181,124+wag));}g.FillEllipse(Brushes.White,174,113+wag,19,17);
  g.FillEllipse(black,56,119,112,84);g.FillEllipse(Brushes.White,66,134,61,61);
  float step=roam&&!sleeping&&pause<=0?(float)Math.Sin(phase*10)*4:0;g.FillEllipse(black,60,173+step,31,39);g.FillEllipse(black,133,172-step,29,40);g.FillEllipse(Brushes.White,57,197+step,37,18);g.FillEllipse(Brushes.White,130,197-step,37,18);
  Point[] ear1={new Point(57,97),new Point(57,43),new Point(92,75)};Point[] ear2={new Point(129,73),new Point(161,43),new Point(165,103)};g.FillPolygon(black,ear1);g.FillPolygon(black,ear2);g.FillPolygon(Brushes.RosyBrown,new Point[]{new Point(63,76),new Point(63,54),new Point(80,76)});g.FillPolygon(Brushes.RosyBrown,new Point[]{new Point(141,76),new Point(156,54),new Point(158,84)});
  g.FillEllipse(black,50,66,120,99);g.FillPolygon(Brushes.White,new Point[]{new Point(106,68),new Point(118,68),new Point(121,106),new Point(141,136),new Point(112,155),new Point(83,137),new Point(103,106)});
  g.FillEllipse(Brushes.White,75,117,73,43);
  if(sleeping){g.DrawArc(outline,70,100,22,10,0,180);g.DrawArc(outline,132,100,22,10,0,180);}else{g.FillEllipse(Brushes.SaddleBrown,72,96,19,23);g.FillEllipse(Brushes.SaddleBrown,132,96,19,23);g.FillEllipse(Brushes.Black,77,99,11,17);g.FillEllipse(Brushes.Black,135,99,11,17);g.FillEllipse(Brushes.White,79,100,5,6);g.FillEllipse(Brushes.White,137,100,5,6);}
  g.FillEllipse(black,100,121,25,16);g.DrawArc(outline,96,131,18,14,0,160);g.DrawArc(outline,112,131,18,14,20,160);if(!sleeping){g.FillEllipse(Brushes.LightCoral,107,142,13,16);}
  using(Pen collar=new Pen(Color.Coral,6))g.DrawArc(collar,76,140,70,27,10,160);g.FillEllipse(Brushes.Gold,107,161,14,14);
 }g.ResetTransform();}
 public void Smoke(){try{if(sheet==null||rows!=13)throw new Exception("assets missing");food=40;Feed();if(food!=62||activity!="eat")throw new Exception("feed");double biteDuration=Count("eat")/Rate("eat");if(Math.Abs(activityLeft-4*biteDuration)>.0001)throw new Exception("four bites duration");Step(3*biteDuration);if(activityLeft<=0||ActionName()!="eat"||food>62)throw new Exception("feeding loops");Step(biteDuration+.01);if(activityLeft>0||ActionName()=="eat"||food>62)throw new Exception("feeding completion");mood=20;energy=80;Play();if(mood!=32||energy!=77)throw new Exception("play");sleeping=true;double before=energy;Step(.1);if(energy<=before)throw new Exception("sleep");sleeping=false;pause=0;activityLeft=0;moving=true;wanderLeft=10;roam=true;direction=1;Left=Screen.PrimaryScreen.WorkingArea.Left+50;int x=Left;for(int n=0;n<60;n++)Step(1.0/60);if(Math.Abs(Left-x-Number("speed",48))>1)throw new Exception("time-based movement");dragging=true;x=Left;Step(.2);if(Left!=x)throw new Exception("drag");dragging=false;
  if(LookDirection(0,-100)!=0||LookDirection(100,0)!=4||LookDirection(0,100)!=8||LookDirection(-100,0)!=12)throw new Exception("gaze cardinal");
  food=62;SaveState();food=0;LoadState();if(food<61)throw new Exception("persistence");
  string[] actions={"idle","walkRight","walkLeft","wave","jump","sad","wait","think","review","eat","sleep"};string dir=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"qa");Directory.CreateDirectory(dir);
  foreach(string action in actions){if(!cfg.ContainsKey(action)||Number(action,-1)<0||Number(action,-1)>=rows)throw new Exception("mapping "+action);Begin(action,action);using(Bitmap b=RenderFrame()){
   if(b.GetPixel(0,0).A!=0)throw new Exception("background alpha");int semi=0;for(int yy=160;yy<368;yy++)for(int xx=0;xx<Width;xx++){Color pixel=b.GetPixel(xx,yy);if(pixel.A>0&&pixel.A<255)semi++;if(pixel.A>20&&pixel.R>pixel.G+60&&pixel.B>pixel.G+60&&pixel.B>pixel.R*.85){b.Save(Path.Combine(dir,"fringe-failure.png"));throw new Exception("purple fringe "+action+" at "+xx+","+yy+" color "+pixel);}}
   if(semi==0)throw new Exception("missing soft alpha "+action);b.Save(Path.Combine(dir,action+".png"));
   foreach(Color bg in new Color[]{Color.White,Color.FromArgb(30,35,42)})using(Bitmap composite=new Bitmap(Width,Height)){using(Graphics cg=Graphics.FromImage(composite)){cg.Clear(bg);cg.DrawImageUnscaled(b,0,0);}composite.Save(Path.Combine(dir,action+(bg==Color.White?"-light":"-dark")+".png"));}
   Present(b);
  }}
  int sw=sheet.Width/cols,sh=sheet.Height/rows;Rectangle anchor=FrameBounds(0,Number("idle",0),sw,sh);int fixedLeft=Left;
  sleeping=true;activityLeft=0;roam=true;panelVisible=false;pause=0;
  for(int f=0;f<Count("sleep");f++){
   int sr=Number("sleep",12);Rectangle bounds=FrameBounds(f,sr,sw,sh);RectangleF dest=SpriteDestination("sleep",f,sr,sw,sh,1);
   if(Math.Abs(dest.X+(bounds.Left+bounds.Right)/2f-(54+(anchor.Left+anchor.Right)/2f))>.01||Math.Abs(dest.Y+bounds.Bottom-(160+anchor.Bottom))>.01)throw new Exception("sleep anchor "+f);
   animationTime=f/Rate("sleep");renderedAction="sleep";using(Bitmap b=RenderFrame())b.Save(Path.Combine(dir,"sleep-aligned-"+f+".png"));Step(.016);if(Left!=fixedLeft)throw new Exception("sleep moved window");
  }
  sleeping=false;
  panelVisible=false;Begin("idle","Anny");using(Bitmap b=RenderFrame()){for(int y=0;y<150;y++)for(int xx=0;xx<Width;xx++)if(b.GetPixel(xx,y).A!=0)throw new Exception("idle UI visible");b.Save(Path.Combine(dir,"ui-rest.png"));}
  HoverStep(new Point(150,250),.016);if(!panelVisible)throw new Exception("hover show");using(Bitmap b=RenderFrame()){if(b.GetPixel(15,15).A==0)throw new Exception("panel missing");b.Save(Path.Combine(dir,"ui-hover.png"));Present(b);}
  HoverStep(new Point(50,120),.6);if(!panelVisible)throw new Exception("panel reach");HoverStep(new Point(-100,-100),.5);if(panelVisible)throw new Exception("hover hide");
  double prior=food;QuickAction(0);if(food<=prior&&prior<100)throw new Exception("quick feed");QuickAction(2);if(!sleeping)throw new Exception("quick sleep");QuickAction(2);if(sleeping)throw new Exception("quick wake");panelVisible=false;
  for(int k=0;k<16;k++){testLook=k;using(Bitmap b=RenderFrame()){if(b.GetPixel(0,0).A!=0)throw new Exception("look background");b.Save(Path.Combine(dir,"look-"+k+".png"));Present(b);}}testLook=-1;  Begin("jump","test");Step(2);if(activityLeft>0)throw new Exception("action end");File.WriteAllText(Path.Combine(dir,"result.txt"),"PASS: all 11 mappings/render, timed actions, frame-rate-independent movement, drag pause, gaze cardinals, feed/play/sleep, persistence. Main sheet loaded. Per-pixel alpha + transparent corners + soft edges + no purple fringe in 11 actions + native UpdateLayeredWindow + all 16 gaze renders; hidden rest UI, hover reveal/reach/hide, quick buttons; all sleep frames center/ground alignment and stationary window; four feeding cycles and completion PASS.");File.Delete(statePath);
 }catch(Exception ex){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"test-error.txt"),ex.ToString());Environment.ExitCode=1;}}
 [STAThread] static void Main(string[] args){bool test=Array.IndexOf(args,"--smoke-test")>=0;bool created;using(Mutex mutex=new Mutex(true,"AnnyDesktopStandaloneV1"+(test?"Test":""),out created)){if(!created)return;Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);using(Pet pet=new Pet(test)){if(test)pet.Smoke();else Application.Run(pet);}}}
}
