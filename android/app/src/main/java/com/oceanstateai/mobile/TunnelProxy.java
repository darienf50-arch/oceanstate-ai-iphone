package com.oceanstateai.mobile;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.Set;
import java.util.concurrent.*;

/** App-only HTTP CONNECT adapter. TLS stays end-to-end and WebView checks the host pin. */
final class TunnelProxy implements Closeable {
    private final ServerSocket listener;
    private final String host;
    private final int socksPort;
    private final Set<Socket> sockets=ConcurrentHashMap.newKeySet();
    private final ExecutorService workers=new ThreadPoolExecutor(0,48,30,TimeUnit.SECONDS,new SynchronousQueue<>(),task->{Thread t=new Thread(task,"OceanState tunnel stream");t.setDaemon(true);return t;});
    private volatile boolean closed;
    TunnelProxy(String host,int socksPort)throws IOException {
        this.host=host;this.socksPort=socksPort;
        listener=new ServerSocket(0,16,InetAddress.getByName("127.0.0.1"));
        Thread accept=new Thread(()->{
            while(!closed)try{
                Socket client=listener.accept();sockets.add(client);
                try{workers.execute(()->handle(client));}catch(RejectedExecutionException e){discard(client);}
            }catch(IOException e){if(!closed)close();}
        },"OceanState tunnel listener");accept.setDaemon(true);accept.start();
    }
    int port(){return listener.getLocalPort();}
    private void handle(Socket client){
        Socket upstream=null;
        try{
            client.setSoTimeout(15000);client.setTcpNoDelay(true);
            InputStream input=client.getInputStream();ByteArrayOutputStream header=new ByteArrayOutputStream();int tail=0;
            while(header.size()<16384){int value=input.read();if(value<0)return;header.write(value);tail=(tail<<8)|value;if(tail==0x0d0a0d0a)break;}
            String request=header.toString(StandardCharsets.US_ASCII.name());
            String[] first=request.split("\\r\\n",2)[0].split(" ");
            if(!request.endsWith("\r\n\r\n")||first.length!=3||!first[0].equals("CONNECT")||!first[1].equalsIgnoreCase(host+":443")||!first[2].equals("HTTP/1.1")){
                client.getOutputStream().write("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".getBytes(StandardCharsets.US_ASCII));return;
            }
            upstream=new Socket(new Proxy(Proxy.Type.SOCKS,new InetSocketAddress("127.0.0.1",socksPort)));sockets.add(upstream);
            upstream.connect(InetSocketAddress.createUnresolved(host,443),45000);upstream.setTcpNoDelay(true);
            client.getOutputStream().write("HTTP/1.1 200 Connection Established\r\n\r\n".getBytes(StandardCharsets.US_ASCII));
            client.setSoTimeout(0);final Socket remote=upstream;
            workers.execute(()->{try{copy(input,remote.getOutputStream());}catch(IOException ignored){}finally{discard(client);discard(remote);}});
            copy(upstream.getInputStream(),client.getOutputStream());
        }catch(IOException|RejectedExecutionException ignored){}finally{discard(client);discard(upstream);}
    }
    private static void copy(InputStream input,OutputStream output)throws IOException{byte[] buffer=new byte[16384];int count;while((count=input.read(buffer))!=-1){output.write(buffer,0,count);output.flush();}}
    private void discard(Socket socket){if(socket==null)return;sockets.remove(socket);try{socket.close();}catch(IOException ignored){}}
    @Override public void close(){closed=true;try{listener.close();}catch(IOException ignored){}for(Socket socket:sockets)discard(socket);workers.shutdownNow();}
}
