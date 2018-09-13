#import "CDVMQTTPlugin.h"

@implementation CDVMQTTPlugin
{
    MQTTSession *mysession;
    NSString *onConnectCallbackId; //回调id
    BOOL *closeMQTT;
}

- (void)connect:(CDVInvokedUrlCommand *)command
{
    onConnectCallbackId = command.callbackId;
    [self.commandDelegate runInBackground:^{
      NSLog(@"start connection");
      MQTTSSLSecurityPolicyTransport *transport = [[MQTTSSLSecurityPolicyTransport alloc] init];
      NSLog(@"%@", [command.arguments objectAtIndex:0]);
      NSString *host = [command.arguments objectAtIndex:0];
      int port = (int)[[command.arguments objectAtIndex:1] integerValue];
      transport.host = host;
      transport.port = port;
      NSDictionary *options = nil;
      NSDictionary *will = nil;
      BOOL ssl = false;
      closeMQTT = false;
      if (![[command.arguments objectAtIndex:2] isKindOfClass:[NSNull class]])
      {
          options = [command.arguments objectAtIndex:2];
          will = [options objectForKey:@"will"];
      }
      if ([options objectForKey:@"clientId"])
          mysession.clientId = [options objectForKey:@"clientId"];
      if ([options objectForKey:@"username"])
          mysession.userName = [options objectForKey:@"username"];
      if ([options objectForKey:@"password"])
          mysession.password = [options objectForKey:@"password"];
      if ([options objectForKey:@"ssl"])
          ssl = [[options objectForKey:@"ssl"] boolValue] ? YES : NO;
      if ([options objectForKey:@"keepAlive"])
          mysession.keepAliveInterval = [[options objectForKey:@"keepAlive"] integerValue];
      if ([[options allKeys] containsObject:@"cleanSession"])
          mysession.cleanSessionFlag = [[options objectForKey:@"cleanSession"] boolValue] ? YES : NO;
      if ([options objectForKey:@"protocol"])
          mysession.protocolLevel = [[options objectForKey:@"protocol"] integerValue];
      if (will)
      {
          mysession.willFlag = TRUE;
          mysession.willTopic = [will objectForKey:@"topic"];
          mysession.willMsg = [will objectForKey:@"message"];
          mysession.willQoS = [[will objectForKey:@"qos"] integerValue];
          mysession.willRetainFlag = [will objectForKey:@"retain"];
      }
      transport.tls = ssl;

      //MQTTSSLSecurityPolicy *policy = [MQTTSSLSecurityPolicy policyWithPinningMode:MQTTSSLPinningModeCertificate];
      //policy.allowInvalidCertificates = YES;
      //policy.validatesDomainName = NO;
      //policy.validatesCertificateChain = NO;

      mysession = [[MQTTSession alloc] init];
      mysession.transport = transport;
      //监听
      [mysession addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionOld context:nil];
      mysession.delegate = self;

      [mysession connectWithConnectHandler:^(NSError *error) {
        CDVPluginResult *pluginResult = nil;
        if (error == nil)
        {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"connect success"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
        else
        {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"connect error"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
      }];
    }];
}

- (void)connected:(MQTTSession *)session
{
    NSDictionary *status = @{
        @"status" : [NSNumber numberWithInt:1]
    };
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:status options:0 error:&error];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    int statusRes = (int)[[status valueForKey:@"status"] intValue];
    if (statusRes == 1)
    {
        jsonString = @"连接成功";
    }
    else if (statusRes == 0)
    {
        jsonString = @"连接失败";
    }
    [self.commandDelegate evalJs:[NSString stringWithFormat:@"mqtt.onConnect('%@')", jsonString]];
}

//发送消息
- (void)publish:(CDVInvokedUrlCommand *)command
{
    [self.commandDelegate runInBackground:^{
      int cacheId = (int)[command.arguments objectAtIndex:0];
      NSString *topic = [command.arguments objectAtIndex:1];
      NSString *message = [command.arguments objectAtIndex:2];
      //        NSData* Data = [message dataUsingEncoding: NSUTF8StringEncoding];
      int qos = (int)[[command.arguments objectAtIndex:3] integerValue];
      BOOL retained = [command.arguments objectAtIndex:4];
      //        [mysession publishData:Data onTopic:topic retain:retained qos:qos];
      UInt16 msgID = [mysession publishData:[message dataUsingEncoding:NSUTF8StringEncoding] onTopic:topic retain:retained qos:qos];

      NSLog(@"publish(%d) %@ %@ %d %d", msgID, topic, message, qos, retained);
      NSDictionary *msg = @{
          @"cacheId" : [NSNumber numberWithInt:cacheId],
          @"topic" : topic,
          @"message" : message,
          @"qos" : [NSNumber numberWithInt:qos],
          @"retain" : [NSNumber numberWithBool:retained]
      };
      NSError *error;
      NSData *jsonData = [NSJSONSerialization dataWithJSONObject:msg options:0 error:&error];
      NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
      CDVPluginResult *pluginResult = nil;
      if (qos == 0)
      {
          pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonString];
          [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
      }
      else if (msgID > 0)
      {
          pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonString];
          [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
      }
      else
      {
          pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error: Message not published"];
          [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
      }
    }];
}

- (void)subscribe:(CDVInvokedUrlCommand *)command
{
    [self.commandDelegate runInBackground:^{
      NSString *topic = [command.arguments objectAtIndex:0];
      int qos = (int)[[command.arguments objectAtIndex:1] integerValue];
      [mysession subscribeToTopic:topic atLevel:qos];
      NSLog(@"subscribe success");
      CDVPluginResult *pluginResult = nil;
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"subscribe success"];
      [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
      //        [self.commandDelegate evalJs:[NSString stringWithFormat:@"mqtt.onSubscribe('%s')", "subscribe success"]];
    }];
}

- (void)unsubscribe:(CDVInvokedUrlCommand *)command
{
    [self.commandDelegate runInBackground:^{
      NSString *topic = [command.arguments objectAtIndex:0];
      [mysession unsubscribeTopic:topic];
      NSLog(@"unsubscribe success");
      CDVPluginResult *pluginResult = nil;
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"unsubscribe success"];
      [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
      //        [self.commandDelegate evalJs:[NSString stringWithFormat:@"mqtt.onUnsubscribe('%s')", "unsubscribe success"]];
    }];
}

- (void)disconnect:(CDVInvokedUrlCommand *)command
{
    [self.commandDelegate runInBackground:^{
      closeMQTT = true;
      //    [mysession disconnect];
      [mysession closeWithDisconnectHandler:^(NSError *error) {
        NSLog(@"disConnect MQTT");
        CDVPluginResult *pluginResult = nil;
        if (error == nil)
        {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"closeMQTT"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
        else
        {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"close error"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
      }];
    }];
}



#pragma MARK MQTTSessionDelegate 以下是代理的方法
//接收的消息在这里处理
- (void)newMessage:(MQTTSession *)session data:(NSData *)data onTopic:(NSString *)topic qos:(MQTTQosLevel)qos retained:(BOOL)retained mid:(unsigned int)mid
{
    NSLog(@"receive message");
    //这个是代理回调方法，接收到的数据可以在这里打印
    //使用字符类型格式化，也可以用json
    NSString *message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self.commandDelegate evalJs:[NSString stringWithFormat:@"mqtt.onMessage('%@')", message]];
}

//重新连接的监听方法
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context
{
    if (mysession.status == 4 && closeMQTT == false)
    {
        NSLog(@"reconnect");
        [mysession connect];
    }
}

- (void)connectionRefused:(MQTTSession *)session error:(NSError *)error
{
    NSLog(@"connect refuse");
    [self.commandDelegate evalJs:[NSString stringWithFormat:@"mqtt.onConnectError('%@');", [error localizedDescription]]];
}

- (void)connectionError:(MQTTSession *)session error:(NSError *)error
{
    [self.commandDelegate evalJs:[NSString stringWithFormat:@"mqtt.onConnectError('%@');", [error localizedDescription]]];
}

- (void)connectionClosed:(MQTTSession *)session
{
    NSDictionary *status = @{
        @"status" : [NSNumber numberWithInt:0]
    };
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:status options:0 error:&error];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSLog(@"connect closed");
    [self.commandDelegate evalJs:[NSString stringWithFormat:@"mqtt.onDisconnect('%@')", jsonString]];
}

@end
