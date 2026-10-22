package com.oceanstateai.mobile;
import org.junit.Test;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import static org.junit.Assert.*;
public class TunnelProxyTest {
    private static String header(InputStream in)throws IOException{ByteArrayOutputStream out=new ByteArrayOutputStream();int tail=0;while(out.size()<16384){int b=in.read();if(b<0)break;out.write(b);tail=(tail<<8)|b;if(tail==0x0d0a0d0a)break;}return out.toString("US-ASCII");}
    @Test(timeout=15000) public void forwardsOpaqueBytesThroughRemoteNameSocks()throws Exception{
        try(ServerSocket socks=new ServerSocket(0,1,InetAddress.getByName("127.0.0.1"));TunnelProxy proxy=new TunnelProxy("test-host.onion",socks.getLocalPort())){
            CompletableFuture<Void> peer=CompletableFuture.runAsync(()->{try(Socket s=socks.accept()){
                s.setSoTimeout(5000);DataInputStream in=new DataInputStream(s.getInputStream());OutputStream out=s.getOutputStream();assertEquals(5,in.readUnsignedByte());int count=in.readUnsignedByte();in.readNBytes(count);out.write(new byte[]{5,0});out.flush();
                assertArrayEquals(new byte[]{5,1,0,3},in.readNBytes(4));String name=new String(in.readNBytes(in.readUnsignedByte()),StandardCharsets.US_ASCII);assertEquals("test-host.onion",name);assertEquals(443,in.readUnsignedShort());
                out.write(new byte[]{5,0,0,1,127,0,0,1,0,0});out.flush();assertArrayEquals("PING".getBytes(StandardCharsets.US_ASCII),in.readNBytes(4));out.write("PONG".getBytes(StandardCharsets.US_ASCII));out.flush();
            }catch(IOException e){throw new CompletionException(e);}});
            try(Socket client=new Socket("127.0.0.1",proxy.port())){client.setSoTimeout(5000);client.getOutputStream().write("CONNECT test-host.onion:443 HTTP/1.1\r\nHost: test-host.onion:443\r\n\r\n".getBytes(StandardCharsets.US_ASCII));assertTrue(header(client.getInputStream()).startsWith("HTTP/1.1 200"));client.getOutputStream().write("PING".getBytes(StandardCharsets.US_ASCII));assertArrayEquals("PONG".getBytes(StandardCharsets.US_ASCII),client.getInputStream().readNBytes(4));}
            peer.get(5,TimeUnit.SECONDS);
        }
    }
    @Test(timeout=10000) public void rejectsOtherHostsPortsAndNonConnectRequests()throws Exception{
        try(TunnelProxy proxy=new TunnelProxy("test-host.onion",9)){
            for(String line:new String[]{"CONNECT other.onion:443 HTTP/1.1","CONNECT test-host.onion:80 HTTP/1.1","GET https://test-host.onion/ HTTP/1.1"}){
                try(Socket client=new Socket("127.0.0.1",proxy.port())){client.setSoTimeout(2000);client.getOutputStream().write((line+"\r\n\r\n").getBytes(StandardCharsets.US_ASCII));assertTrue(header(client.getInputStream()).startsWith("HTTP/1.1 403"));}
            }
        }
    }
}
