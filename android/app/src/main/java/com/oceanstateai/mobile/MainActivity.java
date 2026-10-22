package com.oceanstateai.mobile;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.net.Uri;
import android.net.http.SslError;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.webkit.*;
import android.webkit.CookieManager;
import android.widget.*;
import androidx.webkit.*;
import org.json.JSONObject;
import org.torproject.jni.TorService;
import javax.net.ssl.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.cert.*;
import java.util.concurrent.*;

public final class MainActivity extends Activity {
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final CountDownLatch torBound=new CountDownLatch(1);
    private volatile TorService tor;
    private volatile int socksPort;
    private volatile boolean destroyed;
    private boolean bound,tunnel;
    private String origin="",theme="ocean",pendingDownload;
    private WebView web;
    private TextView status;
    private FrameLayout content;
    private Atmosphere animation;
    private ValueCallback<Uri[]> chooser;
    private PermissionRequest mediaPermission;
    private TabletSession tabletSession;
    private Button controlButton;
    private final ServiceConnection service=new ServiceConnection(){
        @Override public void onServiceConnected(ComponentName name,IBinder binder){tor=((TorService.LocalBinder)binder).getService();torBound.countDown();}
        @Override public void onServiceDisconnected(ComponentName name){tor=null;}
    };
    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        theme=getPreferences(MODE_PRIVATE).getString("theme","ocean");
        LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(Color.rgb(2,11,28));
        root.setOnApplyWindowInsetsListener((view,insets)->{android.graphics.Insets bars=insets.getInsets(WindowInsets.Type.systemBars());view.setPadding(bars.left,bars.top,bars.right,bars.bottom);return insets;});
        LinearLayout bar=new LinearLayout(this);bar.setGravity(Gravity.CENTER_VERTICAL);bar.setPadding(12,4,8,4);
        status=new TextView(this);status.setTextColor(Color.WHITE);status.setTextSize(12);status.setText("Ocean State AI\nConnecting to your host…");bar.addView(status,new LinearLayout.LayoutParams(0,64,1));
        Button themes=new Button(this);themes.setText("Theme");themes.setContentDescription("Choose animated theme");themes.setOnClickListener(v->chooseTheme());bar.addView(themes);
        Button lessons=new Button(this);lessons.setText("Learn");lessons.setContentDescription("Optionally share a useful lesson");lessons.setOnClickListener(v->shareLesson());bar.addView(lessons);
        controlButton=new Button(this);controlButton.setText("Control");controlButton.setOnClickListener(v->toggleControl());bar.addView(controlButton);
        root.addView(bar);content=new FrameLayout(this);root.addView(content,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);
        connect();
    }
    private void message(String value){runOnUiThread(()->status.setText("Ocean State AI\n"+value));}
    private void connect(){
        worker.execute(()->{
            if(probe(HostPolicy.LAN,false)){show(HostPolicy.LAN,false);return;}
            message("Starting private tunnel… First connection may take minutes.");
            runOnUiThread(()->{
                if(!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)){connectionFailed("Update Android System WebView to use the private tunnel.");return;}
                if(!bound){bound=bindService(new Intent(this,TorService.class),service,BIND_AUTO_CREATE);}
            });
            try{
                if(!torBound.await(35,TimeUnit.SECONDS))throw new IOException("Tunnel could not start.");
                for(int attempt=0;attempt<30&&!destroyed;attempt++){
                    TorService active=tor;if(active!=null)socksPort=active.getSocksPort();
                    if(socksPort>0&&probe(HostPolicy.ONION,true)){show(HostPolicy.ONION,true);return;}
                    Thread.sleep(2000);
                }
                if(!destroyed)runOnUiThread(()->connectionFailed("Keep the host online. Try another network if Tor is blocked."));
            }catch(Exception e){if(!destroyed)runOnUiThread(()->connectionFailed("Tunnel unavailable. Keep the host online and retry."));}
        });
    }
    private void connectionFailed(String text){
        message(text);new AlertDialog.Builder(this).setTitle("Connection needs attention").setMessage(text).setPositiveButton("Retry",(d,w)->connect()).setNegativeButton("Close",null).show();
    }
    private HttpsURLConnection connection(String url,boolean throughTor)throws Exception{
        String expectedOrigin=throughTor?HostPolicy.ONION:HostPolicy.LAN;
        if(!HostPolicy.sameOrigin(expectedOrigin,url))throw new IOException("Unrecognized host.");
        URL target=new URL(url);
        Proxy proxy=throughTor?new Proxy(Proxy.Type.SOCKS,new InetSocketAddress("127.0.0.1",socksPort)):Proxy.NO_PROXY;
        HttpsURLConnection result=(HttpsURLConnection)target.openConnection(proxy);
        SSLContext tls=SSLContext.getInstance("TLS");
        tls.init(null,new TrustManager[]{new X509TrustManager(){
            public X509Certificate[] getAcceptedIssuers(){return new X509Certificate[0];}
            public void checkClientTrusted(X509Certificate[] chain,String type)throws CertificateException{throw new CertificateException("No client certificates.");}
            public void checkServerTrusted(X509Certificate[] chain,String type)throws CertificateException{if(chain.length==0||!HostPolicy.pinned(target.getHost(),chain[0]))throw new CertificateException("Host certificate changed.");}
        }},null);
        result.setSSLSocketFactory(tls.getSocketFactory());
        // Exact origin and exact leaf pin are both enforced above, before any credentials.
        result.setHostnameVerifier((host,session)->host.equals(target.getHost())&&HostPolicy.PINS.containsKey(host));
        result.setInstanceFollowRedirects(false);result.setConnectTimeout(10000);result.setReadTimeout(15000);return result;
    }
    private boolean probe(String base,boolean throughTor){
        HttpsURLConnection request=null;try{request=connection(base+"/api/config",throughTor);return request.getResponseCode()==200;}catch(Exception e){return false;}finally{if(request!=null)request.disconnect();}
    }
    @SuppressWarnings("SetJavaScriptEnabled")
    private void show(String base,boolean throughTor){runOnUiThread(()->{
        if(destroyed)return;origin=base;tunnel=throughTor;
        Runnable open=()->{
            if(destroyed)return;
            web=new WebView(this);web.setBackgroundColor(Color.rgb(2,11,28));
            WebSettings settings=web.getSettings();settings.setJavaScriptEnabled(true);settings.setDomStorageEnabled(true);settings.setAllowFileAccess(false);settings.setAllowContentAccess(true);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);settings.setMediaPlaybackRequiresUserGesture(true);
            CookieManager.getInstance().setAcceptCookie(true);CookieManager.getInstance().setAcceptThirdPartyCookies(web,false);
            web.setWebViewClient(new WebViewClient(){
                @Override public void onPageFinished(WebView view,String url){applyTheme();installDeviceHeaders();CookieManager.getInstance().flush();}
                @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
                    String url=request.getUrl().toString();if(HostPolicy.sameOrigin(origin,url))return false;
                    if(request.hasGesture()&&"https".equals(request.getUrl().getScheme())){try{startActivity(new Intent(Intent.ACTION_VIEW,request.getUrl()));}catch(Exception ignored){}}
                    return true;
                }
                @Override public void onReceivedSslError(WebView view,SslErrorHandler handler,SslError error){
                    try{
                        byte[] der=android.net.http.SslCertificate.saveState(error.getCertificate()).getByteArray("x509-certificate");
                        X509Certificate leaf=(X509Certificate)CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(der));
                        if(HostPolicy.sameOrigin(origin,error.getUrl())&&HostPolicy.pinned(Uri.parse(origin).getHost(),leaf)){handler.proceed();return;}
                    }catch(Exception ignored){}
                    handler.cancel();message("Host certificate could not be verified.");
                }
                @Override public void onReceivedError(WebView view,WebResourceRequest request,WebResourceError error){if(request.isForMainFrame())message("Connection interrupted. Use Back or reopen the app to retry.");}
            });
            web.setWebChromeClient(new WebChromeClient(){
                @Override public boolean onShowFileChooser(WebView view,ValueCallback<Uri[]> callback,FileChooserParams params){
                    if(chooser!=null)chooser.onReceiveValue(null);chooser=callback;
                    try{startActivityForResult(params.createIntent(),101);return true;}catch(Exception e){chooser=null;return false;}
                }
                @Override public void onPermissionRequest(PermissionRequest request){runOnUiThread(()->{
                    if(!HostPolicy.sameOrigin(origin,request.getOrigin().toString())){request.deny();return;}
                    mediaPermission=request;
                    java.util.ArrayList<String> permissions=new java.util.ArrayList<>();
                    for(String resource:request.getResources()){
                        if(resource.equals(PermissionRequest.RESOURCE_AUDIO_CAPTURE))permissions.add(Manifest.permission.RECORD_AUDIO);
                        else if(resource.equals(PermissionRequest.RESOURCE_VIDEO_CAPTURE))permissions.add(Manifest.permission.CAMERA);
                        else{request.deny();mediaPermission=null;return;}
                    }
                    requestPermissions(permissions.toArray(new String[0]),102);
                });}
                @Override public void onPermissionRequestCanceled(PermissionRequest request){if(mediaPermission==request)mediaPermission=null;}
            });
            web.setDownloadListener((url,agent,disposition,mime,size)->{
                if(!HostPolicy.sameOrigin(origin,url)){Toast.makeText(this,"Use a direct server download link for this file.",Toast.LENGTH_LONG).show();return;}
                pendingDownload=url;
                Intent save=new Intent(Intent.ACTION_CREATE_DOCUMENT).setType(mime==null?"application/octet-stream":mime).addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE,URLUtil.guessFileName(url,disposition,mime));startActivityForResult(save,103);
            });
            content.removeAllViews();content.addView(web,new FrameLayout.LayoutParams(-1,-1));animation=new Atmosphere();content.addView(animation,new FrameLayout.LayoutParams(-1,-1));web.loadUrl(origin);applyTheme();message(throughTor?"Private tunnel • AI on 4090 host":"Direct connection • AI on 4090 host");
        };
        if(throughTor)ProxyController.getInstance().setProxyOverride(new ProxyConfig.Builder().addProxyRule("socks://127.0.0.1:"+socksPort).build(),getMainExecutor(),open);
        else if(WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE))ProxyController.getInstance().clearProxyOverride(getMainExecutor(),open);
        else open.run();
    });}
    private void chooseTheme(){
        String[] ids={"classic","matrix","ocean"};String[] labels={"Midnight • quiet and clean","Matrix • emerald code rain","Deep Ocean • blue currents"};int selected=theme.equals("matrix")?1:theme.equals("ocean")?2:0;
        new AlertDialog.Builder(this).setTitle("Choose your atmosphere").setSingleChoiceItems(labels,selected,(dialog,index)->{theme=ids[index];getPreferences(MODE_PRIVATE).edit().putString("theme",theme).apply();applyTheme();dialog.dismiss();}).setNegativeButton("Done",null).show();
    }
    private void applyTheme(){
        int accent=theme.equals("matrix")?Color.rgb(103,250,156):Color.rgb(112,216,255);status.setTextColor(accent);if(animation!=null)animation.invalidate();
        if(web==null)return;
        String palette=theme.equals("matrix")?"--color-gray-950:#010a05;--color-gray-900:#04140b;--color-gray-850:#092016;--color-gray-800:#103323;--os-accent:#67fa9c;":theme.equals("ocean")?"--color-gray-950:#020b20;--color-gray-900:#04182c;--color-gray-850:#08263e;--color-gray-800:#0c354f;--os-accent:#70d8ff;":"--color-gray-950:#070a10;--color-gray-900:#0d1420;--color-gray-850:#111b29;--color-gray-800:#192436;--os-accent:#67e8f9;";
        String css=":root,.dark{"+palette+"}html,body{background:var(--color-gray-950)!important;color-scheme:dark}button,input,textarea{transition:background-color .2s,border-color .2s}button:focus-visible,input:focus-visible,textarea:focus-visible{outline:2px solid var(--os-accent)!important;outline-offset:2px}@media(prefers-reduced-motion:reduce){*{transition:none!important}}";
        web.evaluateJavascript("(()=>{let s=document.getElementById('oceanstate-mobile-theme');if(!s){s=document.createElement('style');s.id='oceanstate-mobile-theme';document.head.append(s)}s.textContent="+JSONObject.quote(css)+"})()",null);
    }
    private String login(){String cookies=CookieManager.getInstance().getCookie(origin);if(cookies==null)return "";for(String item:cookies.split(";")){String value=item.trim();if(value.startsWith("token="))return value.substring(6);}return "";}
    private void toggleControl(){
        if(tabletSession!=null&&tabletSession.enabled()){tabletSession.stop();tabletSession=null;controlButton.setText("Control");message("Tablet control stopped");return;}
        if(origin.isEmpty()||login().isEmpty()){Toast.makeText(this,"Connect and sign in first.",Toast.LENGTH_LONG).show();return;}
        new AlertDialog.Builder(this).setTitle("Allow host assistance on this tablet?")
            .setMessage("While enabled, your signed-in Ocean State host can inspect visible controls, request screenshots, tap, type and navigate on this tablet. No continuous screen or keyboard recording. Android blocks protected screens. You can stop control here or disable the Accessibility service at any time. Your tablet cannot control the host.\n\nAndroid requires you to enable Ocean State tablet control in Accessibility Settings once, then return here and enable this session.")
            .setNegativeButton("Cancel",null).setPositiveButton(TabletAccessibility.instance==null?"Open Settings":"Enable this session",(dialog,which)->{
                if(TabletAccessibility.instance==null){startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));return;}
                try{
                    tabletSession=new TabletSession(this,this::relayPost,new TabletSession.Listener(){public void status(String text){message(text);}public void changed(){runOnUiThread(()->{controlButton.setText(tabletSession!=null&&tabletSession.enabled()?"Stop":"Control");installDeviceHeaders();});}});
                    tabletSession.start(login());
                }catch(Exception e){Toast.makeText(this,"Could not prepare tablet control.",Toast.LENGTH_LONG).show();}
            }).show();
    }
    private JSONObject relayPost(String path,JSONObject body,String credential)throws Exception{
        HttpsURLConnection request=connection(origin+"/remote/"+path,tunnel);
        try{
            request.setRequestMethod("POST");request.setDoOutput(true);request.setRequestProperty("Authorization","Bearer "+credential);request.setRequestProperty("Content-Type","application/json");
            try(OutputStream output=request.getOutputStream()){output.write(body.toString().getBytes(StandardCharsets.UTF_8));}
            if(request.getResponseCode()!=200)throw new IOException("Relay request rejected.");
            try(InputStream input=request.getInputStream();ByteArrayOutputStream bytes=new ByteArrayOutputStream()){byte[] buffer=new byte[8192];int count;while((count=input.read(buffer))!=-1){if(bytes.size()+count>1024*1024)throw new IOException("Oversized relay response.");bytes.write(buffer,0,count);}return new JSONObject(bytes.toString(StandardCharsets.UTF_8.name()));}
        }finally{request.disconnect();}
    }
    private void installDeviceHeaders(){
        if(web==null)return;
        try{
            JSONObject device=new JSONObject().put("id",tabletSession!=null?tabletSession.id:"").put("secret",tabletSession!=null?tabletSession.secret:"");
            web.evaluateJavascript("(()=>{window.__oceanDevice="+device+";if(window.__oceanFetch)return;window.__oceanFetch=window.fetch;window.fetch=function(input,options){const r=new Request(input,options),d=window.__oceanDevice;if(new URL(r.url).origin===location.origin&&d&&d.id){const h=new Headers(r.headers);h.set('X-OceanState-Device-Id',d.id);h.set('X-OceanState-Device-Session',d.secret);return window.__oceanFetch.call(this,new Request(r,{headers:h}));}return window.__oceanFetch.call(this,r);};})()",null);
        }catch(Exception ignored){}
    }
    private void shareLesson(){
        if(origin.isEmpty()){Toast.makeText(this,"Connect and sign in first.",Toast.LENGTH_SHORT).show();return;}
        LinearLayout form=new LinearLayout(this);form.setOrientation(LinearLayout.VERTICAL);form.setPadding(35,12,35,12);
        TextView info=new TextView(this);info.setText("Optional: share only the text you submit. No automatic screen, keyboard or other-app capture. Omit passwords and private details. This is user-confirmed reference knowledge.");form.addView(info);
        EditText problem=new EditText(this);problem.setHint("Problem");problem.setMaxLines(4);form.addView(problem);
        EditText solution=new EditText(this);solution.setHint("What worked and how you checked it");solution.setMaxLines(6);form.addView(solution);
        new AlertDialog.Builder(this).setTitle("Share a lesson").setView(form).setNegativeButton("Cancel",null).setPositiveButton("Share this text",(d,w)->{
            String token=login();String p=problem.getText().toString(),s=solution.getText().toString();if(token.isEmpty()||p.trim().isEmpty()||s.trim().isEmpty()){Toast.makeText(this,"Sign in and complete both fields.",Toast.LENGTH_LONG).show();return;}
            worker.execute(()->{
                HttpsURLConnection request=null;try{
                    request=connection(origin+"/remote/file-mobile-lesson",tunnel);request.setRequestMethod("POST");request.setDoOutput(true);request.setRequestProperty("Authorization","Bearer "+token);request.setRequestProperty("Content-Type","application/json");
                    byte[] data=new JSONObject().put("consent",true).put("problem",p.substring(0,Math.min(1000,p.length()))).put("solution",s.substring(0,Math.min(2500,s.length()))).toString().getBytes(StandardCharsets.UTF_8);
                    try(OutputStream output=request.getOutputStream()){output.write(data);}boolean saved=request.getResponseCode()==200;
                    runOnUiThread(()->Toast.makeText(this,saved?"Lesson shared as user-confirmed knowledge.":"Could not save. Check sign-in and connection.",Toast.LENGTH_LONG).show());
                }catch(Exception e){runOnUiThread(()->Toast.makeText(this,"Lesson was not saved. Check your connection.",Toast.LENGTH_LONG).show());}finally{if(request!=null)request.disconnect();}
            });
        }).show();
    }
    @Override protected void onActivityResult(int request,int result,Intent data){
        super.onActivityResult(request,result,data);
        if(request==101&&chooser!=null){chooser.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result,data));chooser=null;}
        if(request==103&&result==RESULT_OK&&data!=null&&pendingDownload!=null){Uri destination=data.getData();String url=pendingDownload;pendingDownload=null;String token=login();worker.execute(()->{
            HttpsURLConnection download=null;try{download=connection(url,tunnel);download.setReadTimeout(120000);if(!token.isEmpty())download.setRequestProperty("Authorization","Bearer "+token);if(download.getResponseCode()!=200)throw new IOException();try(InputStream input=download.getInputStream();OutputStream output=getContentResolver().openOutputStream(destination)){if(output==null)throw new IOException();byte[] buffer=new byte[65536];int count;while((count=input.read(buffer))!=-1)output.write(buffer,0,count);}runOnUiThread(()->Toast.makeText(this,"File saved.",Toast.LENGTH_SHORT).show());}
            catch(Exception e){runOnUiThread(()->Toast.makeText(this,"Download interrupted; the file may be incomplete.",Toast.LENGTH_LONG).show());}finally{if(download!=null)download.disconnect();}
        });}
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] results){super.onRequestPermissionsResult(request,permissions,results);if(request==102&&mediaPermission!=null){boolean granted=results.length>0;for(int value:results)granted&=value==PackageManager.PERMISSION_GRANTED;if(granted)mediaPermission.grant(mediaPermission.getResources());else mediaPermission.deny();mediaPermission=null;}}
    @Override public void onBackPressed(){if(web!=null&&web.canGoBack())web.goBack();else super.onBackPressed();}
    @Override protected void onPause(){super.onPause();if(web!=null)web.onPause();}
    @Override protected void onResume(){super.onResume();if(web!=null)web.onResume();}
    @Override protected void onDestroy(){destroyed=true;if(tabletSession!=null)tabletSession.stop();if(chooser!=null)chooser.onReceiveValue(null);if(mediaPermission!=null)mediaPermission.deny();if(bound)unbindService(service);if(web!=null){web.stopLoading();web.destroy();}worker.shutdownNow();super.onDestroy();}
    private final class Atmosphere extends View {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        Atmosphere(){super(MainActivity.this);setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);setClickable(false);}
        @Override protected void onDraw(Canvas canvas){
            super.onDraw(canvas);boolean motion=Settings.Global.getFloat(getContentResolver(),Settings.Global.ANIMATOR_DURATION_SCALE,1)!=0;double time=motion?SystemClock.uptimeMillis()/1000.0:0;
            if(theme.equals("matrix")){
                paint.setTypeface(Typeface.MONOSPACE);paint.setTextSize(28);paint.setColor(Color.rgb(103,250,156));
                for(int column=0;column<getWidth()/54+1;column++){double offset=(time*(44+(column*17)%66)+column*166)%(getHeight()+440)-220;for(int row=0;row<9;row++){paint.setAlpha((9-row)*4);canvas.drawText(Character.toString((char)(33+(column*13+row*31+(int)(time*3))%59)),column*54+12,(float)(offset-row*38),paint);}}
            }else if(theme.equals("ocean")){
                paint.setColor(Color.rgb(42,157,242));paint.setAlpha(10);
                for(int layer=0;layer<4;layer++){Path wave=new Path();float baseline=getHeight()*(.3f+layer*.21f);wave.moveTo(0,getHeight());for(int x=0;x<=getWidth()+16;x+=16)wave.lineTo(x,baseline+(float)Math.sin(x/(190.0+layer*54)+time*(.20+layer*.055))*(44+layer*18));wave.lineTo(getWidth(),getHeight());wave.close();canvas.drawPath(wave,paint);}
            }
            if(motion&&!theme.equals("classic"))postInvalidateDelayed(42);
        }
    }
}
