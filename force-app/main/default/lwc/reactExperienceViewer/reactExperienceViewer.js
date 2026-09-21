import { LightningElement, track } from 'lwc';
import getSampleAccounts from '@salesforce/apex/ReactExperienceController.getSampleAccounts';

export default class ReactExperienceViewer extends LightningElement {
    @track count = 0;
    @track accounts = [];
    @track isLoading = false;
    @track errorMessage = null;

    get hasAccounts() {
        return this.accounts && this.accounts.length > 0;
    }

    handleIncrement() {
        this.count += 1;
    }

    handleReset() {
        this.count = 0;
    }

    async handleFetchAccounts() {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const data = await getSampleAccounts();
            if (data && data.length > 0) {
                this.accounts = data;
            } else {
                this.accounts = [];
                this.errorMessage = 'No accounts returned. If viewing as a Guest user, ensure a Guest User Sharing Rule is configured for Account.';
            }
        } catch (error) {
            console.error('Error fetching accounts:', error);
            this.errorMessage = error?.body?.message || error?.message || 'Unable to fetch accounts in current guest context.';
        } finally {
            this.isLoading = false;
        }
    }
}
