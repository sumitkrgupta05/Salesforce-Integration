import { LightningElement, api, track } from 'lwc';
import getAccountContext from '@salesforce/apex/LearnDCAccountCopilotController.getAccountContext';
import sendMessage from '@salesforce/apex/LearnDCAccountCopilotController.sendMessage';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AccountGeminiCopilot extends LightningElement {
    @api recordId; // Injected automatically on Account Record Page

    @track messages = [];
    @track userInput = '';
    @track isThinking = false;
    @track accountDisplayName = 'Loading Context...';
    @track csmEmail = '';

    sessionId = '';
    shouldScrollToBottom = false;

    connectedCallback() {
        this.initSession();
        this.loadAccountContext();
    }

    renderedCallback() {
        if (this.shouldScrollToBottom) {
            this.shouldScrollToBottom = false;
            this.performScroll();
        }
    }

    initSession() {
        this.sessionId = 'account-' + (this.recordId || 'global') + '-' + Date.now();
    }

    async loadAccountContext() {
        try {
            const ctx = await getAccountContext({ accountId: this.recordId });
            if (ctx) {
                this.accountDisplayName = ctx.accountName || 'Active Account';
                this.csmEmail = ctx.csmEmail || '';

                // Add Initial Context-Aware Greeting
                this.messages = [
                    {
                        id: 'init-1',
                        isBot: true,
                        containerClass: 'message-row bot-row slds-m-bottom_small',
                        bubbleClass: 'bubble bot-bubble',
                        formattedText: this.formatMarkdown(ctx.initialGreeting),
                        timeStr: this.getCurrentTimeString(),
                        isAccountCard: false,
                        isThreadCard: false,
                        isMeetingCard: false,
                    }
                ];
                this.queueScroll();
            }
        } catch (error) {
            console.error('Error loading account context:', error);
            this.accountDisplayName = 'Account Context';
        }
    }

    get isSendDisabled() {
        return this.isThinking || !this.userInput || this.userInput.trim().length === 0;
    }

    handleInputChange(event) {
        this.userInput = event.target.value;
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && !this.isSendDisabled) {
            event.preventDefault();
            this.handleSendMessage();
        }
    }

    // 1-Click Action Chips
    handleQuickEmailSummary() {
        this.executePrompt('Summarize the recent customer email thread and action items for this account.');
    }

    handleQuickAccountInfo() {
        this.executePrompt('Show me the live account details, assigned CSM, and key contacts from Salesforce.');
    }

    handleQuickScheduleMeeting() {
        this.executePrompt('Schedule a 30-minute review meeting tomorrow at 3 PM with a Google Meet link.');
    }

    executePrompt(promptText) {
        this.userInput = promptText;
        this.handleSendMessage();
    }

    async handleSendMessage() {
        const text = this.userInput ? this.userInput.trim() : '';
        if (!text || this.isThinking) return;

        const userMsgId = 'user-' + Date.now();
        this.messages.push({
            id: userMsgId,
            isBot: false,
            containerClass: 'message-row user-row slds-m-bottom_small',
            bubbleClass: 'bubble user-bubble',
            formattedText: text,
            timeStr: this.getCurrentTimeString(),
            isAccountCard: false,
            isThreadCard: false,
            isMeetingCard: false,
        });

        this.userInput = '';
        this.isThinking = true;
        this.queueScroll();

        try {
            const res = await sendMessage({
                sessionId: this.sessionId,
                userMessage: text,
                accountId: this.recordId
            });

            const botMsgId = 'bot-' + Date.now();
            const isAccountCard = res.messageType === 'accountCard' && res.cardData && Object.keys(res.cardData).length > 0;
            const isThreadCard = res.messageType === 'threadSummaryCard' && res.cardData && Object.keys(res.cardData).length > 0;
            const isMeetingCard = res.messageType === 'meetingCard' && res.cardData && Object.keys(res.cardData).length > 0;

            this.messages.push({
                id: botMsgId,
                isBot: true,
                containerClass: 'message-row bot-row slds-m-bottom_small',
                bubbleClass: 'bubble bot-bubble',
                formattedText: this.formatMarkdown(res.messageText || ''),
                timeStr: this.getCurrentTimeString(),
                isAccountCard,
                isThreadCard,
                isMeetingCard,
                cardData: res.cardData || {}
            });

            // If a meeting was scheduled, automatically refresh native Salesforce Activity Timeline!
            if (res.activityTimelineUpdated && this.recordId) {
                console.log('[GeminiCopilot] Refreshing native Activity Timeline for account:', this.recordId);
                await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Meeting Scheduled & Synced',
                    message: 'Event logged and native Activity Timeline refreshed!',
                    variant: 'success'
                }));
            }

        } catch (err) {
            console.error('Copilot send error:', err);
            this.messages.push({
                id: 'err-' + Date.now(),
                isBot: true,
                containerClass: 'message-row bot-row slds-m-bottom_small',
                bubbleClass: 'bubble bot-bubble',
                formattedText: 'I am unable to complete this request because an unexpected component error occurred: ' + (err.body?.message || err.message || 'Network callout failure') + '. Please refresh the page and try again.',
                timeStr: this.getCurrentTimeString(),
                isAccountCard: false,
                isThreadCard: false,
                isMeetingCard: false,
            });
        } finally {
            this.isThinking = false;
            this.queueScroll();
        }
    }

    handleResetSession() {
        this.initSession();
        this.loadAccountContext();
        this.dispatchEvent(new ShowToastEvent({
            title: 'Session Reset',
            message: 'Chat history cleared. Context refreshed.',
            variant: 'info'
        }));
    }

    queueScroll() {
        this.shouldScrollToBottom = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this.performScroll(), 50);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this.performScroll(), 250);
    }

    performScroll() {
        const feed = this.template.querySelector('.chat-feed');
        if (feed) {
            feed.scrollTop = feed.scrollHeight;
        }
        const rows = this.template.querySelectorAll('.message-row');
        if (rows && rows.length > 0) {
            const lastRow = rows[rows.length - 1];
            if (lastRow.scrollIntoView) {
                lastRow.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
            }
        }
    }

    getCurrentTimeString() {
        const d = new Date();
        return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

    formatMarkdown(text) {
        if (!text) return '';
        let formatted = text;

        // Escape dangerous HTML entities
        formatted = formatted
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');

        // Re-enable bold: **text** -> <strong>text</strong>
        formatted = formatted.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

        // Re-enable inline code: `code` -> <code>code</code>
        formatted = formatted.replace(/`([^`]+)`/g, '<code style="background:#e2e8f0;padding:2px 5px;border-radius:4px;font-size:0.8rem;color:#0f172a;">$1</code>');

        // Bullet points
        formatted = formatted.replace(/\n•\s/g, '<br/>• ');
        formatted = formatted.replace(/\n-\s/g, '<br/>• ');

        // URLs: https://... -> clickable link
        formatted = formatted.replace(/(https?:\/\/[^\s]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer" style="color:#0284c7;text-decoration:underline;">$1</a>');

        // Slack-style links: <url|label>
        formatted = formatted.replace(/&lt;(https?:\/\/[^|]+)\|([^&]+)&gt;/g, '<a href="$1" target="_blank" rel="noopener noreferrer" style="color:#0284c7;text-decoration:underline;">$2</a>');

        // Newlines -> <br/>
        formatted = formatted.replace(/\n/g, '<br/>');

        return formatted;
    }
}
