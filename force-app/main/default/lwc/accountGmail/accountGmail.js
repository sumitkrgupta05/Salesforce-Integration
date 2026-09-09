import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getAccountContext from '@salesforce/apex/AccountGmailController.getAccountContext';
import getAccountEmailThreads from '@salesforce/apex/AccountGmailController.getAccountEmailThreads';
import getThreadDetails from '@salesforce/apex/AccountGmailController.getThreadDetails';
import getOrGenerateThreadSummary from '@salesforce/apex/AccountGmailController.getOrGenerateThreadSummary';
import sendEmail from '@salesforce/apex/AccountGmailController.sendEmail';
import simulateInboundReply from '@salesforce/apex/AccountGmailController.simulateInboundReply';

export default class AccountGmail extends LightningElement {
    @api recordId; // Account Id

    @track threads = [];
    @track threadMessages = [];
    @track contacts = [];
    @track contactOptions = [];

    // AI Summary State
    @track aiSummary = null;
    isAiLoading = false;
    isAiCollapsed = false;

    csmEmail = '';
    userEmail = '';
    searchKey = '';

    selectedThreadId = null;
    selectedThread = null;

    isLoading = false;
    isThreadLoading = false;
    isComposeOpen = false;
    isSending = false;
    isSendingReply = false;

    // Simulate Reply Modal State
    isSimulateReplyOpen = false;
    isSimulating = false;
    simulateContactId = '';
    simulateReplyText = '';

    // Compose Modal Form Fields
    composeContactId = '';
    composeToAddress = '';
    composeCcAddress = '';
    composeSubject = '';
    composeBodyHtml = '';

    // Inline Quick-Reply Field
    replyBody = '';

    // AI Summary State
    isAiExpanded = false;

    // Real-Time Synchronization
    channelName = '/event/Gmail_Sync_Notification__e';
    subscription = {};
    syncTimer = null;
    visibilityHandler = null;

    connectedCallback() {
        this.loadContext();
        this.loadThreads();
        this.initEmpApiSubscription();

        // Real-time synchronization when switching back to this tab/window
        this.visibilityHandler = () => {
            if (document.visibilityState === 'visible') {
                this.silentSync();
            }
        };
        document.addEventListener('visibilitychange', this.visibilityHandler);
        window.addEventListener('focus', this.visibilityHandler);

        // Gentle auto-sync polling every 10 seconds
        this.syncTimer = setInterval(() => {
            this.silentSync();
        }, 10000);
    }

    disconnectedCallback() {
        this.unsubscribeEmpApi();
        if (this.syncTimer) {
            clearInterval(this.syncTimer);
        }
        if (this.visibilityHandler) {
            document.removeEventListener('visibilitychange', this.visibilityHandler);
            window.removeEventListener('focus', this.visibilityHandler);
        }
    }

    // --- Data Loading ---

    async loadContext() {
        if (!this.recordId) return;
        try {
            const ctx = await getAccountContext({ accountId: this.recordId });
            this.csmEmail = ctx.csmEmail || '';
            this.userEmail = ctx.userEmail || '';
            this.contacts = ctx.contacts || [];

            this.contactOptions = this.contacts.map(c => ({
                label: `${c.name} (${c.email})`,
                value: c.id
            }));
        } catch (error) {
            console.error('Error loading account context:', error);
        }
    }

    async loadThreads() {
        if (!this.recordId) return;
        this.isLoading = true;
        try {
            const result = await getAccountEmailThreads({
                accountId: this.recordId,
                searchKey: this.searchKey
            });

            this.threads = (result || []).map(th => ({
                ...th,
                isInbound: th.direction === 'INBOUND',
                isMultipleMessages: th.messageCount > 1,
                messageCountLabel: th.messageCount === 1 ? '1 message' : `${th.messageCount} messages`,
                itemClass: this.computeItemClass(th.threadId)
            }));

            // If a thread was previously selected, refresh reference
            if (this.selectedThreadId) {
                this.selectedThread = this.threads.find(t => t.threadId === this.selectedThreadId) || null;
            } else if (this.threads && this.threads.length > 0) {
                // Auto-select first thread so user immediately sees conversation and AI summary!
                this.selectThread(this.threads[0].threadId);
            }
        } catch (error) {
            console.error('Error loading email threads:', error);
            this.showToast('Error', 'Failed to load email threads: ' + this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async selectThread(threadId) {
        this.selectedThreadId = threadId;
        this.selectedThread = this.threads.find(t => t.threadId === threadId) || null;
        this.updateItemClasses();

        if (!threadId) {
            this.threadMessages = [];
            this.aiSummary = null;
            return;
        }

        this.isThreadLoading = true;
        try {
            const res = await getThreadDetails({ threadId: threadId, accountId: this.recordId });
            if (res && res.thread && res.thread.messages) {
                this.updateThreadMessages(res.thread.messages);

                // Summary returned directly in the same call for instantaneous display!
                if (res.summary) {
                    this.aiSummary = res.summary;
                } else {
                    this.loadThreadAiSummary(threadId, false);
                }
            } else {
                this.threadMessages = [];
            }
        } catch (error) {
            console.error('Error loading thread details:', error);
        } finally {
            this.isThreadLoading = false;
        }
    }

    updateThreadMessages(messages) {
        this.threadMessages = (messages || []).map((msg, index) => {
            const isOutbound = msg.direction === 'OUTBOUND';
            const cleanedBodyHtml = this.stripQuotedText(msg.bodyHtml);
            const cleanedSnippet = this.stripQuotedText(msg.snippet);
            return {
                ...msg,
                bodyHtml: cleanedBodyHtml || msg.bodyHtml,
                snippet: cleanedSnippet || msg.snippet,
                messageIndex: index + 1,
                isReply: index > 0,
                replySeparatorKey: `sep_${msg.id}`,
                isOutbound: isOutbound,
                directionLabel: isOutbound ? 'Sent by You' : 'Customer Reply',
                cardClass: isOutbound ? 'message-card outbound' : 'message-card inbound',
                badgeClass: isOutbound ? 'badge-outbound' : 'badge-inbound',
                avatarIcon: isOutbound ? 'standard:user' : 'standard:avatar'
            };
        });

        if (this.selectedThread) {
            const newCount = this.threadMessages.length;
            this.selectedThread.messageCount = newCount;
            this.selectedThread.isMultipleMessages = newCount > 1;
            this.selectedThread.messageCountLabel = newCount === 1 ? '1 message' : `${newCount} messages`;
        }
    }

    async silentSync() {
        if (!this.recordId || this.isLoading || this.isThreadLoading) return;
        try {
            const result = await getAccountEmailThreads({
                accountId: this.recordId,
                searchKey: this.searchKey
            });

            this.threads = (result || []).map(th => ({
                ...th,
                isInbound: th.direction === 'INBOUND',
                isMultipleMessages: th.messageCount > 1,
                messageCountLabel: th.messageCount === 1 ? '1 message' : `${th.messageCount} messages`,
                itemClass: this.computeItemClass(th.threadId)
            }));

            if (this.selectedThreadId) {
                this.selectedThread = this.threads.find(t => t.threadId === this.selectedThreadId) || null;
                const res = await getThreadDetails({ threadId: this.selectedThreadId, accountId: this.recordId });
                if (res && res.thread && res.thread.messages) {
                    const newLength = res.thread.messages.length;
                    if (newLength !== this.threadMessages.length) {
                        this.updateThreadMessages(res.thread.messages);
                        if (res.summary) {
                            this.aiSummary = res.summary;
                        }
                    }
                }
            } else if (this.threads && this.threads.length > 0) {
                this.selectThread(this.threads[0].threadId);
            }
        } catch (err) {
            console.warn('Silent sync background notice:', err);
        }
    }

    async loadThreadAiSummary(threadId, forceRefresh = false) {
        if (!threadId) return;
        this.isAiLoading = true;
        try {
            const result = await getOrGenerateThreadSummary({
                threadId: threadId,
                accountId: this.recordId,
                forceRefresh: forceRefresh
            });
            if (result) {
                this.aiSummary = result;
            }
        } catch (error) {
            console.error('Error fetching AI thread summary:', error);
        } finally {
            this.isAiLoading = false;
        }
    }

    handleToggleAiCollapse() {
        this.isAiExpanded = !this.isAiExpanded;
    }

    handleRegenerateSummary() {
        if (this.selectedThreadId) {
            this.loadThreadAiSummary(this.selectedThreadId, true);
        }
    }

    // --- Computed Getters ---

    get executiveSummaryText() {
        if (this.aiSummary && this.aiSummary.wholeThreadSummary) {
            return this.aiSummary.wholeThreadSummary;
        }
        if (this.aiSummary && this.aiSummary.executiveSummary) {
            return this.aiSummary.executiveSummary;
        }
        if (this.selectedThread && this.selectedThread.quickSummary) {
            return this.selectedThread.quickSummary;
        }
        if (this.selectedThread && this.selectedThread.snippet) {
            return this.selectedThread.snippet;
        }
        return 'Analyzing conversation turns...';
    }

    get aiModelLabel() {
        return (this.aiSummary && this.aiSummary.modelUsed) ? this.aiSummary.modelUsed : 'Smart AI';
    }

    get hasKeyPointsOrActions() {
        return this.hasKeyPoints || this.hasActionItems;
    }

    get aiToggleBtnLabel() {
        return this.isAiExpanded ? 'Hide Details' : 'View Breakdown';
    }

    get aiCollapseIcon() {
        return this.isAiExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get hasKeyPoints() {
        return this.aiSummary && this.aiSummary.keyPoints && this.aiSummary.keyPoints.length > 0;
    }

    get hasActionItems() {
        return this.aiSummary && this.aiSummary.actionItems && this.aiSummary.actionItems.length > 0;
    }

    get aiSummaryMessageLabel() {
        if (!this.aiSummary) return '';
        const count = this.aiSummary.messageCount || 0;
        return count === 1 ? '1 message' : `${count} messages`;
    }

    get aiGeneratedTimeLabel() {
        if (!this.aiSummary || !this.aiSummary.lastGeneratedAt) return '';
        try {
            const d = new Date(this.aiSummary.lastGeneratedAt);
            return 'Generated ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        } catch (e) {
            return '';
        }
    }

    get fromAddressDisplay() {
        return this.csmEmail || this.userEmail || 'Customer Success Team';
    }

    get hasThreads() {
        return this.threads && this.threads.length > 0;
    }

    get threadCountLabel() {
        const count = this.threads ? this.threads.length : 0;
        return `${count} ${count === 1 ? 'conversation' : 'conversations'}`;
    }

    get isMultipleMessagesSelected() {
        return this.threadMessages && this.threadMessages.length > 1;
    }

    get replyToAddress() {
        // Find clean customer email to reply to
        if (this.threadMessages && this.threadMessages.length > 0) {
            // Find the last inbound message from customer if available
            for (let i = this.threadMessages.length - 1; i >= 0; i--) {
                const msg = this.threadMessages[i];
                if (msg.direction === 'INBOUND' && msg.fromAddress) {
                    return this.extractCleanEmail(msg.fromAddress);
                }
            }
            // Otherwise reply to the recipient of the last outbound message
            const lastMsg = this.threadMessages[this.threadMessages.length - 1];
            if (lastMsg.toAddress) {
                return this.extractCleanEmail(lastMsg.toAddress);
            }
        }
        if (this.selectedThread) {
            if (this.selectedThread.direction === 'INBOUND' && this.selectedThread.fromAddress) {
                return this.extractCleanEmail(this.selectedThread.fromAddress);
            }
            return this.extractCleanEmail(this.selectedThread.toAddress || '');
        }
        return '';
    }

    get lastMessageIdHeader() {
        if (this.threadMessages && this.threadMessages.length > 0) {
            const lastMsg = this.threadMessages[this.threadMessages.length - 1];
            return lastMsg.messageIdHeader || null;
        }
        return null;
    }

    computeItemClass(thId) {
        return thId === this.selectedThreadId ? 'thread-item active' : 'thread-item';
    }

    updateItemClasses() {
        this.threads = this.threads.map(th => ({
            ...th,
            itemClass: this.computeItemClass(th.threadId)
        }));
    }

    extractCleanEmail(rawHeader) {
        if (!rawHeader) return '';
        const start = rawHeader.indexOf('<');
        const end = rawHeader.indexOf('>');
        if (start !== -1 && end !== -1 && end > start) {
            return rawHeader.substring(start + 1, end).trim();
        }
        return rawHeader.trim();
    }

    // --- Search & Refresh ---

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.loadThreads();
    }

    async handleRefresh() {
        await this.loadThreads();
        if (this.selectedThreadId) {
            await this.selectThread(this.selectedThreadId);
        }
        this.showToast('Synced', 'Latest messages and customer replies synced with Gmail.', 'success');
    }

    handleSelectThread(event) {
        const threadId = event.currentTarget.dataset.id;
        this.selectThread(threadId);
    }

    // --- Simulate Client Reply Handlers ---

    handleOpenSimulateReply() {
        this.simulateContactId = this.contacts && this.contacts.length > 0 ? this.contacts[0].id : '';
        this.simulateReplyText = '';
        this.isSimulateReplyOpen = true;
    }

    handleCloseSimulateReply() {
        this.isSimulateReplyOpen = false;
    }

    handleSimulateContactChange(event) {
        this.simulateContactId = event.detail.value;
    }

    handleSimulateTextChange(event) {
        this.simulateReplyText = event.detail.value;
    }

    async handleSendSimulatedReply() {
        if (!this.simulateReplyText || !this.simulateReplyText.trim()) {
            this.showToast('Validation Error', 'Please enter a reply message.', 'error');
            return;
        }

        this.isSimulating = true;
        try {
            const res = await simulateInboundReply({
                accountId: this.recordId,
                contactId: this.simulateContactId,
                threadId: this.selectedThreadId,
                replyText: this.simulateReplyText.trim()
            });

            this.showToast('Reply Received', 'Inbound client reply received and added to thread.', 'success');
            this.handleCloseSimulateReply();

            // Refresh conversations and select thread
            await this.loadThreads();
            const targetThreadId = res.threadId || this.selectedThreadId;
            if (targetThreadId) {
                await this.selectThread(targetThreadId);
            }
        } catch (error) {
            console.error('Error simulating client reply:', error);
            this.showToast('Error', 'Failed to process client reply: ' + this.getErrorMessage(error), 'error');
        } finally {
            this.isSimulating = false;
        }
    }

    // --- Compose Modal Handlers ---

    handleOpenCompose() {
        this.composeContactId = '';
        this.composeToAddress = '';
        this.composeCcAddress = '';
        this.composeSubject = '';
        this.composeBodyHtml = '';
        this.isComposeOpen = true;
    }

    handleCloseCompose() {
        this.isComposeOpen = false;
    }

    handleComposeContactChange(event) {
        this.composeContactId = event.detail.value;
        const matched = this.contacts.find(c => c.id === this.composeContactId);
        if (matched && matched.email) {
            this.composeToAddress = matched.email;
        }
    }

    handleComposeToChange(event) {
        this.composeToAddress = event.target.value;
    }

    handleComposeCcChange(event) {
        this.composeCcAddress = event.target.value;
    }

    handleComposeSubjectChange(event) {
        this.composeSubject = event.target.value;
    }

    handleComposeBodyChange(event) {
        this.composeBodyHtml = event.target.value;
    }

    async handleSendCompose() {
        if (!this.composeToAddress || !this.composeSubject) {
            this.showToast('Required Fields Missing', 'Please enter a recipient email address and subject.', 'warning');
            return;
        }

        this.isSending = true;
        try {
            const res = await sendEmail({
                accountId: this.recordId,
                contactId: this.composeContactId || null,
                toAddress: this.composeToAddress,
                ccAddress: this.composeCcAddress,
                subject: this.composeSubject,
                bodyHtml: this.composeBodyHtml,
                threadId: null,
                inReplyTo: null
            });

            this.showToast('Success', 'Email successfully sent to client!', 'success');
            this.isComposeOpen = false;
            await this.loadThreads();

            const targetThreadId = (res && res.threadId) || (res && res.message && res.message.threadId);
            if (targetThreadId) {
                this.selectThread(targetThreadId);
            }
        } catch (error) {
            console.error('Error sending email:', error);
            this.showToast('Error Sending Email', this.getErrorMessage(error), 'error');
        } finally {
            this.isSending = false;
        }
    }

    // --- Inline Quick-Reply Handlers ---

    handleReplyBodyChange(event) {
        this.replyBody = event.target.value;
    }

    async handleSendReply() {
        if (!this.replyBody || !this.replyBody.trim()) {
            this.showToast('Empty Reply', 'Please write a message before sending.', 'warning');
            return;
        }
        if (!this.selectedThread) return;

        this.isSendingReply = true;
        try {
            const subject = this.selectedThread.subject && this.selectedThread.subject.startsWith('Re:')
                ? this.selectedThread.subject
                : `Re: ${this.selectedThread.subject || ''}`;

            const targetContactId = (this.selectedThread && this.selectedThread.contactId) ? this.selectedThread.contactId : null;
            const res = await sendEmail({
                accountId: this.recordId,
                contactId: targetContactId,
                toAddress: this.replyToAddress,
                ccAddress: null,
                subject: subject,
                bodyHtml: `<p>${this.replyBody.replace(/\n/g, '<br/>')}</p>`,
                threadId: this.selectedThread.threadId,
                inReplyTo: this.lastMessageIdHeader
            });

            this.showToast('Success', 'Reply sent in thread!', 'success');
            this.replyBody = '';

            // Refresh thread conversation view
            const activeThreadId = (res && res.threadId) || this.selectedThread.threadId;
            await this.selectThread(activeThreadId);
            await this.loadThreads();
        } catch (error) {
            console.error('Error sending reply:', error);
            this.showToast('Error Sending Reply', this.getErrorMessage(error), 'error');
        } finally {
            this.isSendingReply = false;
        }
    }

    // --- empApi Live Sync Subscription ---

    initEmpApiSubscription() {
        const messageCallback = (response) => {
            const payload = response && response.data ? response.data.payload : null;
            if (!payload) return;

            const payloadAccId = payload.AccountId__c ? String(payload.AccountId__c).substring(0, 15) : '';
            const currentAccId = this.recordId ? String(this.recordId).substring(0, 15) : '';

            if (!payloadAccId || payloadAccId === currentAccId) {
                this.silentSync();
                this.showToast('Gmail Synced', `New message ${payload.Action__c ? payload.Action__c.toLowerCase() : 'received'} on this Account!`, 'info');
            }
        };

        subscribe(this.channelName, -1, messageCallback).then((res) => {
            this.subscription = res;
        }).catch((err) => {
            console.warn('empApi subscribe error:', err);
        });

        onError((error) => {
            console.warn('empApi streaming error:', JSON.stringify(error));
        });
    }

    unsubscribeEmpApi() {
        if (this.subscription && this.subscription.id) {
            unsubscribe(this.subscription, () => {});
        }
    }

    // --- Utilities ---

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unexpected error occurred.';
    }

    /**
     * @description Strips quoted email reply trails (On ... wrote, blockquotes, original message dividers)
     */
    stripQuotedText(content) {
        if (!content) return '';
        let text = content;
        text = text.replace(/<(?:div|blockquote)[^>]*class=["'][^"']*gmail_quote[^"']*["'][^>]*>[\s\S]*/i, '');
        text = text.replace(/<blockquote[^>]*>[\s\S]*/i, '');
        text = text.replace(/<div[^>]*id=["']divRplyFwdMsg["'][^>]*>[\s\S]*/i, '');
        text = text.replace(/-----Original Message-----[\s\S]*/i, '');
        text = text.replace(/________________________________[\s\S]*/i, '');
        text = text.replace(/(?:\r?\n|^)\s*On\s+.{5,200}\s+wrote:\s*[\s\S]*/i, '');
        text = text.replace(/(?:\r?\n|^)\s*From:\s*.{1,120}\r?\n\s*Sent:\s*.{1,100}\r?\n\s*To:\s*[\s\S]*/i, '');
        return text.trim();
    }
}
