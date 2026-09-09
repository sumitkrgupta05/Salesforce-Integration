import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getAccountContext from '@salesforce/apex/SlackBotAgentController.getAccountContext';
import sendMessage from '@salesforce/apex/SlackBotAgentController.sendMessage';
import getChatThreads from '@salesforce/apex/SlackBotAgentController.getChatThreads';
import getThreadMessages from '@salesforce/apex/SlackBotAgentController.getThreadMessages';
import renameThread from '@salesforce/apex/SlackBotAgentController.renameThread';
import togglePinThread from '@salesforce/apex/SlackBotAgentController.togglePinThread';
import getSlackIdentityContext from '@salesforce/apex/SlackBotAgentController.getSlackIdentityContext';
import disconnectSlackAccount from '@salesforce/apex/SlackBotAgentController.disconnectSlackAccount';
import reSyncSlackIdentity from '@salesforce/apex/SlackBotAgentController.reSyncSlackIdentity';
import authenticateWithSlack from '@salesforce/apex/SlackBotAgentController.authenticateWithSlack';
import authenticateWithSlackCredentials from '@salesforce/apex/SlackBotAgentController.authenticateWithSlackCredentials';
import getSlackOAuthUrl from '@salesforce/apex/SlackBotAgentController.getSlackOAuthUrl';
import getGcpSlackAuthUrl from '@salesforce/apex/SlackBotAgentController.getGcpSlackAuthUrl';
import getGcpSlackAuthUrlForEmail from '@salesforce/apex/SlackBotAgentController.getGcpSlackAuthUrlForEmail';
import getWorkspaceMembers from '@salesforce/apex/SlackBotAgentController.getWorkspaceMembers';
import linkWorkspaceMember from '@salesforce/apex/SlackBotAgentController.linkWorkspaceMember';

export default class SlackBotAgent extends LightningElement {
    @api recordId;

    @track messages = [];
    @track inputMessage = '';
    @track isThinking = false;
    @track showSlashMenu = false;
    @track notificationsEnabled = true;
    @track notificationPermission = (typeof window !== 'undefined' && 'Notification' in window) ? Notification.permission : 'unsupported';

    // Left Navbar Thread History State
    @track threads = [];
    @track threadSearchKey = '';
    @track isSidebarOpen = true;
    @track isLoadingThreads = false;
    @track activeThreadTitle = '';
    @track activeThreadSlackUrl = '';
    @track isLoadingThreadHistory = false;
    @track editingThreadTs = null;
    @track editingTitle = '';

    // Slack Identity & Authentication State
    @track isSettingsOpen = false;
    @track slackIdentity = null;
    @track isAuthenticatingSlack = false;
    @track workspaceMembers = [];
    @track selectedWorkspaceUserId = '';
    @track slackAuthEmail = '';
    boundHandleOAuthMessage = null;

    accountName = '';
    csmEmail = '';
    industry = '';
    sessionId = '';
    threadTs = null;
    previousRecordId = null;
    feedElement = null;
    originalDocumentTitle = '';
    titleFlashInterval = null;

    connectedCallback() {
        this.sessionId = 'slack-bot-' + (this.recordId || 'global') + '-' + Date.now();
        this.previousRecordId = this.recordId;
        this.boundHandleOAuthMessage = this.handleOAuthMessage.bind(this);
        window.addEventListener('message', this.boundHandleOAuthMessage);
        this.loadChatThreads();
        this.loadSlackIdentity();
    }

    disconnectedCallback() {
        if (this.boundHandleOAuthMessage) {
            window.removeEventListener('message', this.boundHandleOAuthMessage);
        }
    }

    renderedCallback() {
        if (!this.feedElement) {
            this.feedElement = this.template.querySelector('.chat-feed');
            this.performRender();
        }
    }

    get hasThreads() {
        return this.filteredThreads && this.filteredThreads.length > 0;
    }

    get threadCount() {
        return this.threads ? this.threads.length : 0;
    }

    get sidebarButtonVariant() {
        return this.isSidebarOpen ? 'brand' : 'border-filled';
    }

    get sidebarToggleTooltip() {
        return this.isSidebarOpen ? 'Hide Thread History' : 'Show Thread History';
    }

    get inputPlaceholder() {
        return this.threadTs 
            ? 'Reply in this Slack thread...' 
            : 'Ask a question or type / for slash commands...';
    }

    get thinkingStatusText() {
        return this.isLoadingThreadHistory 
            ? 'Loading Slack thread history...' 
            : 'Slack Bot Agent is thinking & executing tools...';
    }

    get filteredThreads() {
        if (!this.threads) return [];
        let list = this.threads;
        if (this.threadSearchKey && this.threadSearchKey.trim().length > 0) {
            const key = this.threadSearchKey.trim().toLowerCase();
            list = list.filter(t => 
                (t.title && t.title.toLowerCase().includes(key)) || 
                (t.preview && t.preview.toLowerCase().includes(key))
            );
        }
        return list.map(t => ({
            ...t,
            isSelected: t.threadTs === this.threadTs,
            isEditing: t.threadTs === this.editingThreadTs,
            isPinned: !!t.isPinned,
            pinTooltip: t.isPinned ? 'Unpin thread' : 'Pin thread to top',
            pinButtonClass: 'thread-icon-btn' + (t.isPinned ? ' pinned-active' : ''),
            pinIconText: t.isPinned ? '📌' : '📍',
            itemClass: 'thread-nav-item' + 
                (t.threadTs === this.threadTs ? ' active-thread' : '') +
                (t.isPinned ? ' is-pinned' : '')
        }));
    }

    get threadGroups() {
        const allThreads = this.filteredThreads;
        if (!allThreads || allThreads.length === 0) return [];

        const groups = [];

        // 1. Pinned Group (if any are pinned)
        const pinned = allThreads.filter(t => t.isPinned);
        if (pinned.length > 0) {
            groups.push({
                id: 'group-pinned',
                label: '📌 Pinned',
                count: pinned.length,
                threads: pinned
            });
        }

        // 2. Date Groups (excluding pinned to avoid duplicate rendering)
        const unpinned = allThreads.filter(t => !t.isPinned);
        const dateOrder = ['Today', 'Yesterday', 'Previous 7 Days', 'Previous 30 Days', 'Older'];

        for (const grpName of dateOrder) {
            const grpItems = unpinned.filter(t => (t.dateGroup || 'Today') === grpName);
            if (grpItems.length > 0) {
                groups.push({
                    id: 'group-' + grpName.toLowerCase().replace(/\s+/g, '-'),
                    label: grpName,
                    count: grpItems.length,
                    threads: grpItems
                });
            }
        }

        // Catch any remaining uncategorized
        const categorizedIds = new Set();
        groups.forEach(g => g.threads.forEach(t => categorizedIds.add(t.threadTs)));
        const uncategorized = allThreads.filter(t => !categorizedIds.has(t.threadTs));
        if (uncategorized.length > 0) {
            groups.push({
                id: 'group-other',
                label: 'Other',
                count: uncategorized.length,
                threads: uncategorized
            });
        }

        return groups;
    }

    get notificationIconName() {
        if (this.notificationPermission === 'granted' && this.notificationsEnabled) {
            return 'utility:notification';
        }
        return 'utility:volume_off';
    }

    get notificationButtonVariant() {
        return (this.notificationPermission === 'granted' && this.notificationsEnabled) ? 'brand' : 'border-filled';
    }

    get notificationTooltip() {
        if (this.notificationPermission === 'granted') {
            return this.notificationsEnabled 
                ? 'Desktop Notifications: ON (Click to mute)' 
                : 'Desktop Notifications: OFF (Click to unmute)';
        }
        return 'Click to enable Desktop Notifications';
    }

    @wire(getAccountContext, { accountId: '$recordId' })
    wiredAccountContext({ error, data }) {
        if (this.recordId !== this.previousRecordId) {
            this.previousRecordId = this.recordId;
            this.threadTs = null;
            this.activeThreadTitle = '';
            this.activeThreadSlackUrl = '';
            this.sessionId = 'slack-bot-' + (this.recordId || 'global') + '-' + Date.now();
            this.messages = [];
            this.clearFeedDom();
            this.loadChatThreads();
        }

        if (data) {
            this.accountName = data.accountName || '';
            this.csmEmail = data.csmEmail || '';
            this.industry = data.industry || '';
            if (data.slackIdentity) {
                this.slackIdentity = data.slackIdentity;
            }

            if (this.messages.length === 0) {
                this.addBotMessage(data.initialGreeting);
            }
        } else if (error && this.messages.length === 0) {
            this.addBotMessage('👋 Hi! I am your Slack Bot Agent, powered by Gemini 3.6 Flash. Type `/help` for slash commands or ask any question!');
        }
    }

    async handleToggleNotifications() {
        if (typeof window === 'undefined' || !('Notification' in window)) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Notifications Unsupported',
                message: 'Desktop Notifications are not supported by this browser environment.',
                variant: 'info'
            }));
            return;
        }

        if (Notification.permission === 'default') {
            try {
                const perm = await Notification.requestPermission();
                this.notificationPermission = perm;
                this.notificationsEnabled = (perm === 'granted');
                if (perm === 'granted') {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Notifications Enabled',
                        message: 'You will receive desktop alerts when AI responses complete in the background.',
                        variant: 'success'
                    }));
                }
            } catch (e) {
                console.warn('Could not request notification permission:', e);
            }
        } else if (Notification.permission === 'granted') {
            this.notificationsEnabled = !this.notificationsEnabled;
            this.dispatchEvent(new ShowToastEvent({
                title: this.notificationsEnabled ? 'Notifications Unmuted' : 'Notifications Muted',
                message: this.notificationsEnabled ? 'Desktop alerts are active.' : 'Desktop alerts muted.',
                variant: 'info'
            }));
        } else if (Notification.permission === 'denied') {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Notifications Blocked',
                message: 'Notifications are blocked in your browser settings. Please allow notifications for this site to enable desktop alerts.',
                variant: 'warning'
            }));
        }
    }

    handleInputChange(event) {
        this.inputMessage = event.target.value;
        const trimmed = (this.inputMessage || '').trim();
        // Show slash menu when user types '/' or starts typing a slash command without space
        this.showSlashMenu = trimmed.startsWith('/') && !trimmed.includes(' ');
    }

    handleKeyUp(event) {
        if (event.keyCode === 27) { // Escape key closes menu
            this.showSlashMenu = false;
            return;
        }
        if (event.keyCode === 13 && !this.isSendDisabled) {
            this.showSlashMenu = false;
            this.handleSendMessage();
        }
    }

    handleSelectSlashCommand(event) {
        const cmd = event.currentTarget.dataset.cmd;
        if (cmd) {
            this.inputMessage = cmd;
            this.showSlashMenu = false;
            // Commands ready to execute immediately
            if (cmd === '/help' || cmd === '/account-brief' || cmd === '/snowflake') {
                this.handleSendMessage();
            } else {
                // Focus input for user to type thread ID or account
                const inputEl = this.template.querySelector('lightning-input');
                if (inputEl) inputEl.focus();
            }
        }
    }

    handleChipClick(event) {
        const prompt = event.currentTarget.dataset.prompt;
        if (prompt && !this.isThinking) {
            this.inputMessage = prompt;
            this.showSlashMenu = false;
            this.handleSendMessage();
        }
    }

    handleToggleSidebar() {
        this.isSidebarOpen = !this.isSidebarOpen;
    }

    handleThreadSearchChange(event) {
        this.threadSearchKey = event.target.value;
    }

    handleStopPropagation(event) {
        event.stopPropagation();
    }

    handleStartRename(event) {
        event.stopPropagation();
        const ts = event.currentTarget.dataset.ts;
        const currentTitle = event.currentTarget.dataset.title;
        this.editingThreadTs = ts;
        this.editingTitle = currentTitle || '';

        setTimeout(() => {
            const inputEl = this.template.querySelector('.thread-edit-input');
            if (inputEl) {
                inputEl.focus();
                inputEl.select();
            }
        }, 50);
    }

    handleEditTitleInput(event) {
        this.editingTitle = event.target.value;
    }

    handleEditTitleKeyUp(event) {
        if (event.keyCode === 13) { // Enter
            this.handleSaveRename(event);
        } else if (event.keyCode === 27) { // Escape
            this.handleCancelRename(event);
        }
    }

    handleCancelRename(event) {
        if (event) event.stopPropagation();
        this.editingThreadTs = null;
        this.editingTitle = '';
    }

    async handleSaveRename(event) {
        if (event) event.stopPropagation();
        const ts = this.editingThreadTs;
        const newTitle = (this.editingTitle || '').trim();
        if (!ts || !newTitle) {
            this.handleCancelRename();
            return;
        }

        // Optimistic update in UI
        const previousThreads = JSON.parse(JSON.stringify(this.threads || []));
        const targetThread = (this.threads || []).find(t => t.threadTs === ts);
        if (targetThread) {
            targetThread.title = newTitle;
        }
        if (this.threadTs === ts) {
            this.activeThreadTitle = newTitle;
        }

        this.editingThreadTs = null;
        this.editingTitle = '';
        this.threads = [...this.threads];

        try {
            const res = await renameThread({
                threadTs: ts,
                accountId: this.recordId || null,
                newTitle: newTitle
            });

            if (res && res.isSuccess) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Thread Renamed',
                    message: `Renamed to "${newTitle}". Synced with Slack.`,
                    variant: 'success'
                }));
            } else {
                throw new Error(res?.message || 'Could not rename thread');
            }
        } catch (err) {
            console.error('Rename thread error:', err);
            this.threads = previousThreads;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Rename Failed',
                message: err.body?.message || err.message || 'Callout failure',
                variant: 'error'
            }));
        }
    }

    async handleTogglePin(event) {
        event.stopPropagation();
        const ts = event.currentTarget.dataset.ts;
        const isPinned = event.currentTarget.dataset.pinned === 'true';
        const targetPinned = !isPinned;

        // Optimistic update
        const target = (this.threads || []).find(t => t.threadTs === ts);
        if (target) {
            target.isPinned = targetPinned;
        }
        this.threads = [...this.threads];

        try {
            const res = await togglePinThread({
                threadTs: ts,
                accountId: this.recordId || null,
                isPinned: targetPinned
            });

            if (res && res.isSuccess) {
                this.dispatchEvent(new ShowToastEvent({
                    title: targetPinned ? 'Thread Pinned' : 'Thread Unpinned',
                    message: targetPinned ? 'Thread pinned to top.' : 'Thread unpinned.',
                    variant: 'info'
                }));
            }
        } catch (err) {
            console.error('Toggle pin error:', err);
            if (target) {
                target.isPinned = isPinned;
                this.threads = [...this.threads];
            }
        }
    }

    async loadChatThreads() {
        if (!this.isSlackConnected) {
            this.threads = [];
            this.isLoadingThreads = false;
            return;
        }
        try {
            this.isLoadingThreads = true;
            const data = await getChatThreads({ accountId: this.recordId || null });
            this.threads = data || [];
        } catch (err) {
            console.warn('Could not load chat threads:', err);
        } finally {
            this.isLoadingThreads = false;
        }
    }

    async handleSelectThread(event) {
        const ts = event.currentTarget.dataset.ts;
        if (!ts || ts === this.threadTs) return;

        this.threadTs = ts;
        const threadObj = (this.threads || []).find(t => t.threadTs === ts);
        this.activeThreadTitle = threadObj ? threadObj.title : 'Selected Thread';
        this.activeThreadSlackUrl = threadObj ? threadObj.slackUrl : null;

        this.isLoadingThreadHistory = true;
        this.isThinking = true;
        this.clearFeedDom();

        try {
            const rawMessages = await getThreadMessages({
                threadTs: ts,
                accountId: this.recordId || null
            });

            this.messages = (rawMessages || []).map(m => ({
                id: m.id || ('msg-' + Math.random()),
                isUser: m.isUser,
                text: m.text,
                cardData: m.cardData || null,
                slackThreadUrl: m.slackThreadUrl || null,
                messageType: m.messageType || 'text',
                time: m.timeFormatted || this.getTimeString()
            }));

            this.performRender();
        } catch (err) {
            console.error('Error loading thread messages:', err);
            this.addBotMessage('⚠️ Could not load thread messages: ' + (err.body?.message || err.message));
        } finally {
            this.isLoadingThreadHistory = false;
            this.isThinking = false;
            this.performScroll();
        }
    }

    handleStartNewChat() {
        this.handleResetSession();
    }

    handleResetSession() {
        this.sessionId = 'slack-bot-' + (this.recordId || 'global') + '-' + Date.now();
        this.threadTs = null;
        this.activeThreadTitle = '';
        this.activeThreadSlackUrl = '';
        this.messages = [];
        this.showSlashMenu = false;
        this.clearFeedDom();
        this.addBotMessage(
            '🔄 New conversation started. Type `/help` for slash commands or ask any question!'
        );
    }

    async handleSendMessage() {
        const text = (this.inputMessage || '').trim();
        if (!text || this.isThinking) return;

        // Proactively request notification permission on user gesture if still default
        if (typeof window !== 'undefined' && 'Notification' in window && Notification.permission === 'default') {
            Notification.requestPermission().then(perm => {
                this.notificationPermission = perm;
                this.notificationsEnabled = (perm === 'granted');
            }).catch(() => {});
        }

        this.inputMessage = '';
        this.showSlashMenu = false;
        this.addUserMessage(text);
        this.isThinking = true;
        this.performScroll();

        // Update active thread title preview if this is the start of a new thread
        if (!this.activeThreadTitle) {
            this.activeThreadTitle = text.length > 40 ? text.substring(0, 37) + '...' : text;
        }

        try {
            const res = await sendMessage({
                sessionId: this.sessionId,
                userMessage: text,
                accountId: this.recordId,
                threadTs: this.threadTs
            });

            if (res.slackThreadTs) {
                this.threadTs = res.slackThreadTs;
                this.activeThreadSlackUrl = res.slackThreadUrl;
            }

            this.addBotMessage(
                res.messageText || '',
                res.cardData || null,
                res.slackThreadUrl || null,
                res.messageType || 'text'
            );

            // Refresh thread list in left navbar so active/new thread updates immediately
            this.loadChatThreads();

            // If an action updated timeline, notify record update
            if (res.activityTimelineUpdated && this.recordId) {
                await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            }

            // Dispatch native desktop notification if user switched tabs / windows
            this.dispatchDesktopNotification(res.messageText);

        } catch (err) {
            console.error('SlackBotAgent error:', err);
            this.addBotMessage(
                'I am unable to complete this request because an unexpected error occurred: ' + 
                (err.body?.message || err.message || 'Callout failure') + '. Please try again.'
            );
        } finally {
            this.isThinking = false;
            this.performScroll();
        }
    }

    dispatchDesktopNotification(responseText) {
        // 1. Check if user is away from tab or window
        const isAway = (typeof document !== 'undefined') && (document.hidden || !document.hasFocus());
        if (!isAway) return; // User is already viewing the chat feed

        // 2. Check if desktop notifications are permitted & enabled
        if (!this.notificationsEnabled || typeof window === 'undefined' || !('Notification' in window)) return;
        if (Notification.permission !== 'granted') {
            this.flashDocumentTitle();
            return;
        }

        try {
            // Strip markdown formatting for a clean system notification preview
            let preview = (responseText || 'Response has finished loading.')
                .replace(/\*\*/g, '')
                .replace(/\*/g, '')
                .replace(/`/g, '')
                .replace(/^• /gm, '')
                .replace(/\n+/g, ' ')
                .trim();

            if (preview.length > 110) {
                preview = preview.substring(0, 107) + '...';
            }

            const notifTitle = this.accountName 
                ? `Slack Bot Agent: ${this.accountName}` 
                : 'Slack Bot Agent';

            const notification = new Notification(notifTitle, {
                body: preview,
                tag: 'slack-bot-agent-reply',
                renotify: true
            });

            notification.onclick = () => {
                window.focus();
                this.clearTitleFlash();
                notification.close();
            };

            // Also flash browser tab title
            this.flashDocumentTitle();
        } catch (e) {
            console.warn('Desktop notification dispatch notice:', e);
            this.flashDocumentTitle();
        }
    }

    flashDocumentTitle() {
        if (typeof document === 'undefined') return;
        if (!this.originalDocumentTitle) {
            this.originalDocumentTitle = document.title;
        }

        let toggle = false;
        if (this.titleFlashInterval) clearInterval(this.titleFlashInterval);

        this.titleFlashInterval = setInterval(() => {
            if (!document.hidden && document.hasFocus()) {
                this.clearTitleFlash();
                return;
            }
            document.title = toggle 
                ? '🔔 (1) New Reply Ready | Salesforce' 
                : this.originalDocumentTitle;
            toggle = !toggle;
        }, 1500);

        window.addEventListener('focus', () => this.clearTitleFlash(), { once: true });
    }

    clearTitleFlash() {
        if (this.titleFlashInterval) {
            clearInterval(this.titleFlashInterval);
            this.titleFlashInterval = null;
        }
        if (this.originalDocumentTitle && typeof document !== 'undefined') {
            document.title = this.originalDocumentTitle;
        }
    }

    addUserMessage(text) {
        const msg = {
            id: 'user-' + Date.now(),
            isUser: true,
            text: text,
            time: this.getTimeString()
        };
        this.messages.push(msg);
        this.renderMessageInDom(msg);
    }

    addBotMessage(text, cardData, slackThreadUrl, messageType) {
        const msg = {
            id: 'bot-' + Date.now(),
            isUser: false,
            text: text,
            cardData: cardData,
            slackThreadUrl: slackThreadUrl,
            messageType: messageType,
            time: this.getTimeString()
        };
        this.messages.push(msg);
        this.renderMessageInDom(msg);
    }

    clearFeedDom() {
        if (this.feedElement) {
            this.feedElement.innerHTML = '';
        }
    }

    performRender() {
        if (!this.feedElement) return;
        this.feedElement.innerHTML = '';
        this.messages.forEach(msg => this.renderMessageInDom(msg));
        this.performScroll();
    }

    renderMessageInDom(msg) {
        if (!this.feedElement) return;

        const row = document.createElement('div');
        row.className = 'message-row ' + (msg.isUser ? 'user-row' : 'bot-row');

        const bubble = document.createElement('div');
        bubble.className = 'bubble ' + (msg.isUser ? 'user-bubble' : 'bot-bubble');

        // Style slash commands specially in user bubble
        if (msg.isUser && msg.text && msg.text.startsWith('/')) {
            bubble.innerHTML = `<span class="user-command-tag">⚡ COMMAND</span> ${this.formatMarkdown(msg.text)}`;
        } else {
            bubble.innerHTML = this.formatMarkdown(msg.text);
        }

        // Append embedded card if available
        if (msg.cardData && Object.keys(msg.cardData).length > 0) {
            const card = this.createCardDom(msg.messageType, msg.cardData);
            if (card) bubble.appendChild(card);
        }

        // Append Slack Thread deeplink button if available
        if (msg.slackThreadUrl) {
            const linkBtn = document.createElement('a');
            linkBtn.href = msg.slackThreadUrl;
            linkBtn.target = '_blank';
            linkBtn.rel = 'noopener noreferrer';
            linkBtn.className = 'slack-link-btn';
            linkBtn.innerHTML = '💬 View in Slack History';
            bubble.appendChild(linkBtn);
        }

        const time = document.createElement('span');
        time.className = 'message-time';
        time.innerText = msg.time;

        row.appendChild(bubble);
        row.appendChild(time);
        this.feedElement.appendChild(row);

        this.performScroll();
    }

    createCardDom(type, data) {
        const card = document.createElement('div');
        card.className = 'embedded-card';

        if (type === 'accountCard') {
            let snowflakeSection = '';
            if (data.healthScore !== undefined && data.healthScore !== null) {
                const score = Number(data.healthScore);
                const badgeClass = score >= 80 ? 'health-badge-good' : (score >= 60 ? 'health-badge-warning' : 'health-badge-danger');
                const badgeIcon = score >= 80 ? '🟢' : (score >= 60 ? '🟡' : '🔴');
                const rating = score >= 80 ? 'EXCELLENT' : (score >= 60 ? 'FAIR' : 'AT RISK');

                snowflakeSection = `
                    <div class="card-divider"></div>
                    <div class="card-section-title">📊 Account Health &amp; Platform Utilization</div>
                    <div class="snowflake-metrics-grid">
                        <div class="metric-box">
                            <span class="metric-label">Health Score</span>
                            <span class="metric-value ${badgeClass}">${badgeIcon} ${score}/100 <small>(${rating})</small></span>
                        </div>
                        <div class="metric-box">
                            <span class="metric-label">Monthly Usage</span>
                            <span class="metric-value">⏱️ ${data.usageHours || 0} hrs</span>
                        </div>
                        <div class="metric-box">
                            <span class="metric-label">Churn Risk</span>
                            <span class="metric-value">🛡️ ${data.churnRisk || 'LOW'}</span>
                        </div>
                        <div class="metric-box">
                            <span class="metric-label">SLA Tier</span>
                            <span class="metric-value">⭐ ${data.slaTier || 'Standard'}</span>
                        </div>
                    </div>
                    <div class="snowflake-footer-note">
                        <span class="snowflake-chip">📊 Account Intelligence</span>
                        <span class="sync-time">&bull; Active &bull; ${data.snowflakeSyncTime || 'Up to date'}</span>
                    </div>
                `;
            }

            let threadSection = '';
            if (data.executiveSummary) {
                threadSection = `
                    <div class="card-divider"></div>
                    <div class="card-section-title">📝 Recent Activity &amp; Communications</div>
                    <div class="card-field"><span class="card-value">${data.executiveSummary}</span></div>
                    ${data.actionItems ? `<div class="card-field"><span class="card-label">Action Items:</span> <span class="card-value">${data.actionItems}</span></div>` : ''}
                `;
            }

            card.innerHTML = `
                <div class="card-section-title">📋 Account Overview</div>
                <div class="card-field"><span class="card-label">Account:</span> <span class="card-value"><strong>${data.accountName || ''}</strong></span></div>
                <div class="card-field"><span class="card-label">Account Manager:</span> <span class="card-value">${data.csmEmail || 'None'}</span></div>
                <div class="card-field"><span class="card-label">Primary Contact:</span> <span class="card-value">${data.primaryContactName || 'None'} (${data.primaryContactEmail || 'None'})</span></div>
                <div class="card-field"><span class="card-label">Industry:</span> <span class="card-value">${data.industry || 'Technology'}</span></div>
                ${snowflakeSection}
                ${threadSection}
            `;
        } else if (type === 'snowflakeCard') {
            const score = Number(data.healthScore || 85);
            const badgeClass = score >= 80 ? 'health-badge-good' : (score >= 60 ? 'health-badge-warning' : 'health-badge-danger');
            const badgeIcon = score >= 80 ? '🟢' : (score >= 60 ? '🟡' : '🔴');
            const rating = score >= 80 ? 'EXCELLENT' : (score >= 60 ? 'FAIR' : 'AT RISK');

            card.innerHTML = `
                <div class="card-section-title">📊 Account Health &amp; Platform Utilization</div>
                <div class="card-field"><span class="card-label">Account:</span> <span class="card-value"><strong>${data.accountName || ''}</strong></span></div>
                <div class="snowflake-metrics-grid slds-m-top_x-small">
                    <div class="metric-box">
                        <span class="metric-label">Health Score</span>
                        <span class="metric-value ${badgeClass}">${badgeIcon} ${score}/100 <small>(${rating})</small></span>
                    </div>
                    <div class="metric-box">
                        <span class="metric-label">Monthly Usage</span>
                        <span class="metric-value">⏱️ ${data.usageHours || 0} hrs</span>
                    </div>
                    <div class="metric-box">
                        <span class="metric-label">Churn Risk</span>
                        <span class="metric-value">🛡️ ${data.churnRisk || 'LOW'}</span>
                    </div>
                    <div class="metric-box">
                        <span class="metric-label">SLA Tier</span>
                        <span class="metric-value">⭐ ${data.slaTier || 'Standard'}</span>
                    </div>
                </div>
                <div class="snowflake-footer-note">
                    <span class="snowflake-chip">📊 Account Intelligence</span>
                    <span class="sync-time">&bull; Active &bull; ${data.snowflakeSyncTime || 'Up to date'}</span>
                </div>
            `;
        } else if (type === 'threadSummaryCard') {
            card.innerHTML = `
                <div class="card-field"><span class="card-label">Thread ID:</span> <span class="card-value"><code>${data.threadId || ''}</code> (${data.messageCount || 0} msgs)</span></div>
                <div class="card-field"><span class="card-label">Executive Summary:</span> <span class="card-value">${data.executiveSummary || ''}</span></div>
                ${data.keyPoints ? `<div class="card-field"><span class="card-label">Key Points:</span> <span class="card-value">${data.keyPoints}</span></div>` : ''}
                <div class="card-field"><span class="card-label">Action Items:</span> <span class="card-value">${data.actionItems || 'None'}</span></div>
            `;
        } else if (type === 'meetingCard') {
            card.innerHTML = `
                <div class="card-field"><span class="card-label">Subject:</span> <span class="card-value"><strong>${data.subject || ''}</strong></span></div>
                <div class="card-field"><span class="card-label">Time:</span> <span class="card-value">${data.startDateTimeFormatted || ''}</span></div>
                ${data.googleMeetLink ? `<div class="card-field"><a href="${data.googleMeetLink}" target="_blank" class="slds-button slds-button_brand slds-m-top_xx-small">🎥 Join Google Meet</a></div>` : ''}
            `;
        } else {
            return null;
        }

        return card;
    }

    formatMarkdown(text) {
        if (!text) return '';
        let escaped = text
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');

        // Bold **text**
        escaped = escaped.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
        // Italic *text*
        escaped = escaped.replace(/\*(.*?)\*/g, '<em>$1</em>');
        // Inline code `text`
        escaped = escaped.replace(/`(.*?)`/g, '<code>$1</code>');
        // Bullet points
        escaped = escaped.replace(/^• (.*?)$/gm, '&bull; $1');
        // Line breaks
        escaped = escaped.replace(/\n/g, '<br/>');

        return escaped;
    }

    performScroll() {
        if (this.feedElement) {
            requestAnimationFrame(() => {
                this.feedElement.scrollTop = this.feedElement.scrollHeight;
            });
        }
    }

    getTimeString() {
        const now = new Date();
        return now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

    // =========================================================================
    // SLACK IDENTITY & ISOLATION GETTERS & HANDLERS
    // =========================================================================

    get isSlackConnected() {
        return this.slackIdentity && this.slackIdentity.isConnected;
    }

    get isInputDisabled() {
        return !this.isSlackConnected || this.isThinking;
    }

    get isSendDisabled() {
        return !this.isSlackConnected || !this.inputMessage || this.inputMessage.trim().length === 0 || this.isThinking;
    }

    get inputPlaceholder() {
        if (!this.isSlackConnected) {
            return '🔒 Sign in with Slack to start chatting...';
        }
        return this.threadTs ? 'Reply in this Slack thread...' : 'Ask a question or type / for slash commands...';
    }

    get slackBadgeClass() {
        return this.isSlackConnected
            ? 'slack-badge slds-badge slds-badge_lightest slack-badge-clickable'
            : 'slack-badge slds-badge slds-badge_warning slack-badge-clickable';
    }

    get slackDotClass() {
        return this.isSlackConnected ? 'online-dot' : 'warning-dot';
    }

    get slackBadgeText() {
        if (this.slackIdentity && this.slackIdentity.isConnected) {
            const chan = this.slackIdentity.slackDmChannelId || '';
            return `Slack: Connected 🟢${chan ? ' (' + chan + ')' : ''}`;
        }
        return 'Slack: Sign in with Slack 🟡';
    }

    get slackBadgeTooltip() {
        return this.isSlackConnected
            ? `Connected to private DM ${this.slackIdentity.slackDmChannelId}. Click to manage settings.`
            : 'Slack account not yet connected. Click to sign in with Slack.';
    }

    get userFullName() {
        return this.slackIdentity && this.slackIdentity.userName ? this.slackIdentity.userName : 'Current User';
    }

    get userEmail() {
        return this.slackIdentity && this.slackIdentity.userEmail ? this.slackIdentity.userEmail : '';
    }

    get slackMemberIdDisplay() {
        return this.slackIdentity && this.slackIdentity.slackUserId ? this.slackIdentity.slackUserId : 'Not Linked';
    }

    get slackDmChannelDisplay() {
        return this.slackIdentity && this.slackIdentity.slackDmChannelId ? this.slackIdentity.slackDmChannelId : 'Not Configured';
    }

    get settingsStatusBannerClass() {
        return this.isSlackConnected
            ? 'slds-notify slds-notify_alert slds-theme_success slds-m-bottom_small slds-border_radius'
            : 'slds-notify slds-notify_alert slds-theme_warning slds-m-bottom_small slds-border_radius';
    }

    get settingsStatusEmoji() {
        return this.isSlackConnected ? '🟢' : '🟡';
    }

    get settingsStatusTitle() {
        return this.isSlackConnected ? 'Slack Account Connected & Isolated' : 'Slack Account Pending Setup';
    }

    get settingsStatusDescription() {
        if (this.isSlackConnected) {
            return `All chats are securely synchronized with your private 1-on-1 Slack DM channel (${this.slackIdentity.slackDmChannelId}). Other CSMs cannot see your conversations.`;
        }
        return 'Your Salesforce user account is not connected to Slack. Click "Sign in with Slack" to authenticate.';
    }

    get isDisconnectDisabled() {
        return !this.isSlackConnected;
    }

    async loadSlackIdentity() {
        try {
            const id = await getSlackIdentityContext();
            if (id) {
                this.slackIdentity = id;
            }
        } catch (err) {
            console.warn('[SlackBotAgent] Could not load Slack identity context:', err);
        }
    }

    handleOpenSettings() {
        this.isSettingsOpen = true;
        this.loadSlackIdentity();
        this.loadWorkspaceMembers();
        if (this.slackIdentity && this.slackIdentity.userEmail) {
            const mail = this.slackIdentity.userEmail;
            if (!mail.includes('orgfarm') && !mail.includes('salesforce.com')) {
                this.slackAuthEmail = mail;
            }
        }
    }

    handleCloseSettings() {
        this.isSettingsOpen = false;
    }

    handleSlackAuthEmailChange(event) {
        this.slackAuthEmail = event.target.value;
    }

    handleSlackAuthKeyUp(event) {
        if (event.keyCode === 13) {
            this.handleOfficialSlackLogin();
        }
    }

    get hasWorkspaceMembers() {
        return this.workspaceMembers && this.workspaceMembers.length > 0;
    }

    get workspaceMemberOptions() {
        return (this.workspaceMembers || []).map(m => ({
            label: `${m.realName} (${m.email || m.slackUserId})`,
            value: m.slackUserId
        }));
    }

    async loadWorkspaceMembers() {
        try {
            const members = await getWorkspaceMembers();
            if (members && members.length > 0) {
                this.workspaceMembers = members;
                if (!this.selectedWorkspaceUserId) {
                    this.selectedWorkspaceUserId = members[0].slackUserId;
                    if (!this.slackAuthEmail && members[0].email) {
                        this.slackAuthEmail = members[0].email;
                    }
                }
            }
        } catch (err) {
            console.warn('[SlackBotAgent] Could not load workspace members:', err);
        }
    }

    handleWorkspaceMemberChange(event) {
        this.selectedWorkspaceUserId = event.target.value;
        const member = (this.workspaceMembers || []).find(m => m.slackUserId === this.selectedWorkspaceUserId);
        if (member && member.email) {
            this.slackAuthEmail = member.email;
        }
    }

    async handleLinkSelectedMember() {
        if (!this.selectedWorkspaceUserId) return;
        this.isAuthenticatingSlack = true;
        try {
            const updated = await linkWorkspaceMember({ slackUserId: this.selectedWorkspaceUserId });
            this.slackIdentity = updated;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Slack Connected Successfully',
                message: `Connected to Slack Workspace as ${updated.userName} (${updated.slackDmChannelId})`,
                variant: 'success'
            }));
            this.handleCloseSettings();
            this.loadChatThreads();
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Connection Failed',
                message: err.body ? err.body.message : err.message,
                variant: 'error'
            }));
        } finally {
            this.isAuthenticatingSlack = false;
        }
    }

    handleOAuthMessage(event) {
        if (!event || !event.data) return;
        if (event.data.type === 'SLACK_AUTH_SUCCESS') {
            this.slackIdentity = {
                isConnected: true,
                slackUserId: event.data.slackUserId,
                slackDmChannelId: event.data.slackDmChannelId,
                userName: event.data.userName
            };
            this.dispatchEvent(new ShowToastEvent({
                title: 'Slack Authentication Successful',
                message: `Connected to Slack Workspace as ${event.data.userName} (${event.data.slackDmChannelId})`,
                variant: 'success'
            }));
            this.handleCloseSettings();
            this.loadChatThreads();
            this.loadSlackIdentity();
        } else if (event.data.type === 'SLACK_AUTH_ERROR') {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Slack Authentication Failed',
                message: event.data.message || 'Authorization was cancelled or declined.',
                variant: 'error'
            }));
        }
    }

    async handleOfficialSlackLogin() {
        let emailToAuthenticate = (this.slackAuthEmail || '').trim();

        if (!emailToAuthenticate) {
            const member = (this.workspaceMembers || []).find(m => m.slackUserId === this.selectedWorkspaceUserId);
            if (member && member.email) {
                emailToAuthenticate = member.email;
                this.slackAuthEmail = member.email;
            } else if (this.userEmail) {
                emailToAuthenticate = this.userEmail;
            }
        }

        // Launch GCP-hosted Slack OAuth redirect popup with the Slack Consent Screen
        try {
            const gcpUrl = await getGcpSlackAuthUrlForEmail({ targetEmail: emailToAuthenticate });
            if (gcpUrl) {
                const width = 620, height = 750;
                const left = (window.innerWidth - width) / 2 + window.screenX;
                const top = (window.innerHeight - height) / 2 + window.screenY;
                const popup = window.open(
                    gcpUrl,
                    'SlackOAuthPopup',
                    `width=${width},height=${height},top=${top},left=${left},status=yes,toolbar=no,menubar=no`
                );
                if (popup) {
                    this.authPopup = popup;
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Connecting to Slack',
                        message: 'Please review requested permissions and click "Allow" in the Slack authorization window.',
                        variant: 'info'
                    }));
                    return;
                }
            }
        } catch (e) {
            console.warn('[SlackBotAgent] OAuth popup init notice:', e);
        }

        this.dispatchEvent(new ShowToastEvent({
            title: 'Slack Authorization Window Blocked',
            message: 'Please allow browser popups for this page to complete the Slack OAuth handshake.',
            variant: 'warning'
        }));
    }

    async handleReSyncIdentity() {
        if (this.slackIdentity && this.slackIdentity.userEmail) {
            this.slackAuthEmail = this.slackIdentity.userEmail;
        }
        await this.handleOfficialSlackLogin();
    }

    async handleDisconnectSlack() {
        try {
            await disconnectSlackAccount();
            this.slackIdentity = { isConnected: false, connectionMessage: 'Disconnected' };
            this.dispatchEvent(new ShowToastEvent({
                title: 'Slack Disconnected',
                message: 'Your Slack account binding has been removed.',
                variant: 'info'
            }));
            this.loadChatThreads();
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Disconnect Failed',
                message: err.body ? err.body.message : err.message,
                variant: 'error'
            }));
        }
    }
}
