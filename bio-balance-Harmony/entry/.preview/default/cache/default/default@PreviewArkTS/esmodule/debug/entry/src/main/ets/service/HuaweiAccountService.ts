import authentication from "@hms:core.authentication";
import type common from "@ohos:app.ability.common";
import type { CloudAccountSession } from './CloudSyncTransport';
export class HuaweiAccountService implements CloudAccountSession {
    private context: common.Context;
    constructor(context: common.Context) {
        this.context = context;
    }
    async signIn(interactive: boolean = true): Promise<string> {
        const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
        const request: authentication.LoginWithHuaweiIDRequest = provider.createLoginWithHuaweiIDRequest();
        request.forceLogin = interactive;
        const controller: authentication.AuthenticationController = new authentication.AuthenticationController(this.context);
        const response: authentication.AuthenticationResponse = await controller.executeRequest(request);
        const credential: authentication.LoginWithHuaweiIDCredential | undefined = (response as authentication.LoginWithHuaweiIDResponse).data;
        if (credential === undefined)
            throw new Error('Huawei ID credential unavailable');
        return credential.openID;
    }
    async restoreSession(): Promise<string> {
        try {
            return await this.signIn(false);
        }
        catch (error) {
            return '';
        }
    }
    async currentAccountId(): Promise<string> { return this.restoreSession(); }
    async signOut(): Promise<void> {
        const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
        const controller: authentication.AuthenticationController = new authentication.AuthenticationController(this.context);
        await controller.executeRequest(provider.createCancelAuthorizationRequest());
    }
}
