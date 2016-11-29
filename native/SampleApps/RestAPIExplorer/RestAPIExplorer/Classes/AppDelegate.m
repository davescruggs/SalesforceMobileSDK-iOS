/*
 Copyright (c) 2011-present, salesforce.com, inc. All rights reserved.
 
 Redistribution and use of this software in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of
 conditions and the following disclaimer in the documentation and/or other materials provided
 with the distribution.
 * Neither the name of salesforce.com, inc. nor the names of its contributors may be used to
 endorse or promote products derived from this software without specific prior written
 permission of salesforce.com, inc.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <MobileCoreServices/UTCoreTypes.h>
#import "AppDelegate.h"
#import "InitialViewController.h"
#import "RestAPIExplorerViewController.h"
#import <SalesforceSDKCore/SFJsonUtils.h>
#import <SalesforceSDKCore/SFUserAccountManager.h>
#import <SalesforceSDKCore/SFPushNotificationManager.h>
#import <SalesforceSDKCore/SFDefaultUserManagementViewController.h>
#import <SalesforceSDKCore/SalesforceSDKManager.h>
#import <SalesforceSDKCore/SFLoginViewController.h>
#import <UIKit/UIKit.h>
#import <SalesforceSDKCore/SFAuthenticationManager.h>
#import <SalesforceSDKCore/NSString+SFAdditions.h>

// Fill these in when creating a new Connected Application on Force.com
static NSString * const RemoteAccessConsumerKey = @"3MVG9Iu66FKeHhINkB1l7xt7kR8czFcCTUhgoA8Ol2Ltf1eYHOU4SqQRSEitYFDUpqRWcoQ2.dBv_a1Dyu5xa";
static NSString * const OAuthRedirectURI        = @"testsfdc:///mobilesdk/detect/oauth/done";

@implementation AppDelegate {
    BOOL _jwtAuthenticating;
}

@synthesize window = _window;

- (id)init
{
    self = [super init];
    _jwtAuthenticating = NO;
    
    if (self) {
        #if defined(DEBUG)
            [SFLogger sharedLogger].logLevel = SFLogLevelDebug;
        #else
            [SFLogger sharedLogger].logLevel = SFLogLevelInfo;
        #endif
        [SalesforceSDKManager sharedManager].connectedAppId = RemoteAccessConsumerKey;
        [SalesforceSDKManager sharedManager].connectedAppCallbackUri = OAuthRedirectURI;
        [SalesforceSDKManager sharedManager].authScopes = @[ @"web", @"api" ];
        [SalesforceSDKManager sharedManager].authenticateAtLaunch = NO;
        __weak typeof(self) weakSelf = self;
        [SalesforceSDKManager sharedManager].postLaunchAction = ^(SFSDKLaunchAction launchActionList) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            //
            // If you wish to register for push notifications, uncomment the line below.  Note that,
            // if you want to receive push notifications from Salesforce, you will also need to
            // implement the application:didRegisterForRemoteNotificationsWithDeviceToken: method (below).
            //
            //[[SFPushNotificationManager sharedInstance] registerForRemoteNotifications];
            //
            [strongSelf log:SFLogLevelInfo format:@"Post-launch: launch actions taken: %@", [SalesforceSDKManager launchActionsStringRepresentation:launchActionList]];
        };
        [SalesforceSDKManager sharedManager].launchErrorAction = ^(NSError *error, SFSDKLaunchAction launchActionList) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf log:SFLogLevelError format:@"Error during SDK launch: %@", [error localizedDescription]];
            [strongSelf initializeAppViewState];
            [[SalesforceSDKManager sharedManager] launch];
        };
        [SalesforceSDKManager sharedManager].postLogoutAction = ^{
            [weakSelf handleSdkManagerLogout];
        };
        [SalesforceSDKManager sharedManager].switchUserAction = ^(SFUserAccount *fromUser, SFUserAccount *toUser) {
            [weakSelf handleUserSwitch:fromUser toUser:toUser];
        };
    }
    
    return self;
}

#pragma mark - App delegate lifecycle

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation{
    NSString *urlString = [url absoluteString];
    SFUserAccount *currentAccount = [SFUserAccountManager sharedInstance].currentUser;
    BOOL isAuthenticated = (!currentAccount.isTemporaryUser && !currentAccount.isAnonymousUser && currentAccount.credentials.refreshToken.length > 0);
    
    if ([urlString hasPrefix:@"restapi://magicLink?"] && !isAuthenticated) {
        NSString *jwt = nil;
        NSRange queryStringRange = [urlString rangeOfString:@"?"];
        if (queryStringRange.location != NSNotFound) {
            NSString *queryString = [urlString substringFromIndex:queryStringRange.location + 1];
            NSDictionary *queryStringComponents = [queryString queryStringComponents];
            jwt = queryStringComponents[@"token"];
        }
        if (jwt) {
            [self startAuthentication:jwt];
        }
        return YES;
    }
    
    return NO;
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    [self initializeAppViewState];
    //
    //Uncomment the code below to see how you can customize the color, textcolor, font and fontsize of the navigation bar
    //
    //SFLoginViewController *loginViewController = [SFLoginViewController sharedInstance];
    //Set showNavBar to NO if you want to hide the top bar
    //loginViewController.showNavbar = YES;
    //Set showSettingsIcon to NO if you want to hide the settings icon on the nav bar
    //loginViewController.showSettingsIcon = YES;
    // Set primary color to different color to style the navigation header
    //loginViewController.navBarColor = [UIColor colorWithRed:0.051 green:0.765 blue:0.733 alpha:1.0];
    //loginViewController.navBarFont = [UIFont fontWithName:@"Helvetica" size:16.0];
    //loginViewController.navBarTextColor = [UIColor blackColor];
    //
    
    [[SalesforceSDKManager sharedManager] launch];
    
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    SFUserAccount *currentAccount = [SFUserAccountManager sharedInstance].currentUser;
    BOOL isAuthenticated = (!currentAccount.isTemporaryUser && !currentAccount.isAnonymousUser && currentAccount.credentials.refreshToken.length > 0);
    if (!isAuthenticated) {
        if (!_jwtAuthenticating) {
            [self startAuthentication:nil];
        }
    } else {
        [self setupRootViewController];
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [[SFAuthenticationManager sharedManager] cancelAuthentication];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    //
    // Uncomment the code below to register your device token with the push notification manager
    //
    //[[SFPushNotificationManager sharedInstance] didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
    //if ([SFUserAccountManager sharedInstance].currentUser.credentials.accessToken != nil) {
    //    [[SFPushNotificationManager sharedInstance] registerForSalesforceNotifications];
    //}
    //
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    // Respond to any push notification registration errors here.
}

#pragma mark - Private methods

- (void)initializeAppViewState
{
    self.window.rootViewController = [[InitialViewController alloc] initWithNibName:nil bundle:nil];
    [self.window makeKeyAndVisible];
}

- (void)setupRootViewController
{
    RestAPIExplorerViewController *rootVC = [[RestAPIExplorerViewController alloc] initWithNibName:nil bundle:nil];
    self.window.rootViewController = rootVC;
}

- (void)resetViewState:(void (^)(void))postResetBlock
{
    if ([self.window.rootViewController presentedViewController]) {
        [self.window.rootViewController dismissViewControllerAnimated:NO completion:^{
            postResetBlock();
        }];
    } else {
        postResetBlock();
    }
}

- (void)handleSdkManagerLogout
{
    [self log:SFLogLevelDebug msg:@"SDK Manager logged out.  Resetting app."];
    [self resetViewState:^{
        [self initializeAppViewState];
        
        // Multi-user pattern:
        // - If there are two or more existing accounts after logout, let the user choose the account
        //   to switch to.
        // - If there is one existing account, automatically switch to that account.
        // - If there are no further authenticated accounts, present the login screen.
        //
        // Alternatively, you could just go straight to re-initializing your app state, if you know
        // your app does not support multiple accounts.  The logic below will work either way.
        NSArray *allAccounts = [SFUserAccountManager sharedInstance].allUserAccounts;
        if ([allAccounts count] > 1) {
            SFDefaultUserManagementViewController *userSwitchVc = [[SFDefaultUserManagementViewController alloc] initWithCompletionBlock:^(SFUserManagementAction action) {
                [self.window.rootViewController dismissViewControllerAnimated:YES completion:NULL];
            }];
            [self.window.rootViewController presentViewController:userSwitchVc animated:YES completion:NULL];
        } else {
            if ([allAccounts count] == 1) {
                [SFUserAccountManager sharedInstance].currentUser = ([SFUserAccountManager sharedInstance].allUserAccounts)[0];
            }
            [self startAuthentication:nil];
        }
    }];
}

- (void)handleUserSwitch:(SFUserAccount *)fromUser toUser:(SFUserAccount *)toUser
{
    [self log:SFLogLevelInfo format:@"SFUserAccountManager changed from user %@ to %@.  Resetting app.", fromUser.userName, toUser.userName];
    [self resetViewState:^{
        [self initializeAppViewState];
        [self startAuthentication:nil];
    }];
}

- (void)startAuthentication:(NSString *)jwtToken
{
    SFAuthenticationManager * mgr = [SFAuthenticationManager sharedManager];
    __weak __typeof(self) weakSelf = self;
    if (jwtToken.length > 0) {
        _jwtAuthenticating = YES;
        [mgr loginWithJwtToken:jwtToken completion:^(SFOAuthInfo * _Nonnull authInfo) {
            __strong __typeof(self) strongSelf = weakSelf;
            [strongSelf log:SFLogLevelInfo format:@"Authentication (%@) succeeded.  Launch completed.", authInfo.authTypeDescription];
            [strongSelf setupRootViewController];
            _jwtAuthenticating = NO;
        } failure:^(SFOAuthInfo * _Nonnull authInfo, NSError * _Nonnull authError) {
            __strong __typeof(self) strongSelf = weakSelf;
            [strongSelf log:SFLogLevelError format:@"Authentication (JWTTokenFlow) failed: %@.", authError.localizedDescription];
            _jwtAuthenticating = NO;
        }];
    } else {
        [mgr loginWithCompletion:^(SFOAuthInfo * _Nonnull authInfo) {
            __strong __typeof(self) strongSelf = weakSelf;
            [strongSelf log:SFLogLevelInfo format:@"Authentication (%@) succeeded.  Launch completed.", authInfo.authTypeDescription];
            [strongSelf setupRootViewController];
        } failure:^(SFOAuthInfo * _Nonnull authInfo, NSError * _Nonnull authError) {
            __strong __typeof(self) strongSelf = weakSelf;
            [strongSelf log:SFLogLevelError format:@"Authentication (UserAgentFlow) failed: %@.", authError.localizedDescription];
        }];
    }
}

#pragma mark - Unit test helpers

- (void)exportTestingCredentials {
    //collect credentials and copy to pasteboard
    SFOAuthCredentials *creds = [SFUserAccountManager sharedInstance].currentUser.credentials;
    NSMutableDictionary *configDict = [NSMutableDictionary dictionaryWithDictionary:@{@"test_client_id": RemoteAccessConsumerKey,
                                                                                      @"test_login_domain": [SFUserAccountManager sharedInstance].loginHost,
                                                                                      @"test_redirect_uri": OAuthRedirectURI,
                                                                                      @"refresh_token": creds.refreshToken,
                                                                                      @"instance_url": [creds.instanceUrl absoluteString],
                                                                                      @"identity_url": [creds.identityUrl absoluteString],
                                                                                      @"access_token": @"__NOT_REQUIRED__"}];
    if (creds.communityUrl != nil) {
        configDict[@"community_url"] = [creds.communityUrl absoluteString];
    }
    
    NSString *configJSON = [SFJsonUtils JSONRepresentation:configDict];
    UIPasteboard *gpBoard = [UIPasteboard generalPasteboard];
    [gpBoard setValue:configJSON forPasteboardType:(NSString*)kUTTypeUTF8PlainText];
}

@end
