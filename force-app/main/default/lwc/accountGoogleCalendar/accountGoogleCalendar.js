import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

import getIntegrationStatus from '@salesforce/apex/AccountCalendarController.getIntegrationStatus';
import getAccountContacts from '@salesforce/apex/AccountCalendarController.getAccountContacts';
import getAccountMeetings from '@salesforce/apex/AccountCalendarController.getAccountMeetings';
import createMeeting from '@salesforce/apex/AccountCalendarController.createMeeting';
import rescheduleMeeting from '@salesforce/apex/AccountCalendarController.rescheduleMeeting';
import cancelMeeting from '@salesforce/apex/AccountCalendarController.cancelMeeting';

export default class AccountGoogleCalendar extends LightningElement {
    @api recordId; // Account Record Id

    @track meetings = [];
    @track contacts = [];
    @track isLoading = false;
    @track isModalLoading = false;
    @track showConfigWarning = false;

    // Modals
    @track isScheduleModalOpen = false;
    @track isRescheduleModalOpen = false;
    @track isCancelModalOpen = false;

    // Forms
    @track scheduleForm = {
        subject: '',
        contactId: '',
        additionalEmails: '',
        startDateTime: '',
        endDateTime: '',
        addGoogleMeet: true,
        description: ''
    };

    @track selectedMeeting = {};
    @track rescheduleForm = {
        startDateTime: '',
        endDateTime: ''
    };

    // EmpApi Subscription
    channelName = '/event/Calendar_Sync_Notification__e';
    subscription = {};
    isSubscribed = false;

    connectedCallback() {
        this.loadIntegrationStatus();
        this.loadContacts();
        this.loadMeetings();
        this.registerEmpApiSubscription();
    }

    disconnectedCallback() {
        this.handleUnsubscribe();
    }

    get hasMeetings() {
        return this.meetings && this.meetings.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && (!this.meetings || this.meetings.length === 0);
    }

    get contactOptions() {
        const options = [{ label: '-- None / No Primary Contact --', value: '' }];
        if (this.contacts && this.contacts.length > 0) {
            this.contacts.forEach(c => {
                const titleStr = c.title ? ` (${c.title})` : '';
                options.push({
                    label: `${c.name}${titleStr} - ${c.email || 'No email'}`,
                    value: c.id
                });
            });
        }
        return options;
    }

    // =========================================================
    // DATA LOADERS
    // =========================================================

    async loadIntegrationStatus() {
        try {
            const status = await getIntegrationStatus();
            this.showConfigWarning = !status.isConfigured;
        } catch (error) {
            console.error('Error loading integration status', error);
        }
    }

    async loadContacts() {
        if (!this.recordId) return;
        try {
            this.contacts = await getAccountContacts({ accountId: this.recordId });
        } catch (error) {
            console.error('Error loading contacts', error);
        }
    }

    async loadMeetings() {
        if (!this.recordId) return;
        this.isLoading = true;
        try {
            this.meetings = await getAccountMeetings({ accountId: this.recordId });
        } catch (error) {
            this.showToast('Error Loading Meetings', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleRefresh() {
        this.loadMeetings();
        this.showToast('Refreshed', 'Meetings calendar list refreshed', 'info');
    }

    // =========================================================
    // REAL-TIME EMP-API PLATFORM EVENT LISTENER
    // =========================================================

    registerEmpApiSubscription() {
        const messageCallback = (response) => {
            const payload = response.data.payload;
            // Refresh if matching account or general update
            if (!payload.AccountId__c || payload.AccountId__c === this.recordId) {
                this.loadMeetings();
                this.showToast(
                    'Real-time Update', 
                    `Google Calendar sync received (${payload.Action__c || 'Updated'})`, 
                    'success'
                );
            }
        };

        subscribe(this.channelName, -1, messageCallback).then((response) => {
            this.subscription = response;
            this.isSubscribed = true;
        }).catch((err) => {
            console.warn('Could not subscribe to Platform Event channel', err);
        });

        onError((error) => {
            console.error('EMP API Error: ', JSON.stringify(error));
        });
    }

    handleUnsubscribe() {
        if (this.subscription && this.subscription.channel) {
            unsubscribe(this.subscription, () => {
                this.isSubscribed = false;
            });
        }
    }

    // =========================================================
    // SCHEDULE MODAL HANDLERS
    // =========================================================

    openScheduleModal() {
        // Compute smart defaults: start at next full hour, end 30 mins later
        const now = new Date();
        now.setHours(now.getHours() + 1, 0, 0, 0);
        const startIso = now.toISOString();

        const end = new Date(now.getTime() + 30 * 60000);
        const endIso = end.toISOString();

        this.scheduleForm = {
            subject: '',
            contactId: this.contacts.length > 0 ? this.contacts[0].id : '',
            additionalEmails: '',
            startDateTime: startIso,
            endDateTime: endIso,
            addGoogleMeet: true,
            description: ''
        };
        this.isScheduleModalOpen = true;
    }

    closeScheduleModal() {
        this.isScheduleModalOpen = false;
    }

    handleScheduleInputChange(event) {
        const field = event.target.name;
        const val = event.target.type === 'toggle' || event.target.type === 'checkbox' 
            ? event.target.checked 
            : event.target.value;
        this.scheduleForm = { ...this.scheduleForm, [field]: val };
    }

    handleContactChange(event) {
        this.scheduleForm.contactId = event.detail.value;
    }

    async handleScheduleSubmit() {
        if (!this.scheduleForm.subject) {
            this.showToast('Validation Error', 'Please enter a Meeting Subject', 'warning');
            return;
        }
        if (!this.scheduleForm.startDateTime || !this.scheduleForm.endDateTime) {
            this.showToast('Validation Error', 'Start and End Date/Time are required', 'warning');
            return;
        }

        const start = new Date(this.scheduleForm.startDateTime);
        const end = new Date(this.scheduleForm.endDateTime);
        if (end <= start) {
            this.showToast('Validation Error', 'End Time must be after Start Time', 'warning');
            return;
        }

        // Build attendee email list
        const attendeeList = [];
        if (this.scheduleForm.contactId) {
            const selectedCon = this.contacts.find(c => c.id === this.scheduleForm.contactId);
            if (selectedCon && selectedCon.email) {
                attendeeList.push(selectedCon.email);
            }
        }
        if (this.scheduleForm.additionalEmails) {
            const extra = this.scheduleForm.additionalEmails.split(',').map(e => e.trim()).filter(e => e);
            attendeeList.push(...extra);
        }

        this.isModalLoading = true;
        try {
            await createMeeting({
                accountId: this.recordId,
                subject: this.scheduleForm.subject,
                description: this.scheduleForm.description,
                startDateTime: this.scheduleForm.startDateTime,
                endDateTime: this.scheduleForm.endDateTime,
                attendeeEmails: attendeeList,
                addGoogleMeet: this.scheduleForm.addGoogleMeet,
                contactId: this.scheduleForm.contactId || null
            });

            this.showToast('Success', 'Meeting scheduled & synced to Google Calendar!', 'success');
            this.closeScheduleModal();
            await this.loadMeetings();
        } catch (error) {
            this.showToast('Schedule Failed', this.reduceErrors(error), 'error');
        } finally {
            this.isModalLoading = false;
        }
    }

    // =========================================================
    // RESCHEDULE MODAL HANDLERS
    // =========================================================

    openRescheduleModal(event) {
        const meetingId = event.target.dataset.id;
        const meeting = this.meetings.find(m => m.id === meetingId);
        if (!meeting) return;

        this.selectedMeeting = meeting;
        this.rescheduleForm = {
            startDateTime: meeting.startDateTime,
            endDateTime: meeting.endDateTime
        };
        this.isRescheduleModalOpen = true;
    }

    closeRescheduleModal() {
        this.isRescheduleModalOpen = false;
    }

    handleRescheduleStartChange(event) {
        this.rescheduleForm.startDateTime = event.target.value;
    }

    handleRescheduleEndChange(event) {
        this.rescheduleForm.endDateTime = event.target.value;
    }

    async handleRescheduleSubmit() {
        if (!this.rescheduleForm.startDateTime || !this.rescheduleForm.endDateTime) {
            this.showToast('Validation Error', 'Start and End Date/Time are required', 'warning');
            return;
        }

        const start = new Date(this.rescheduleForm.startDateTime);
        const end = new Date(this.rescheduleForm.endDateTime);
        if (end <= start) {
            this.showToast('Validation Error', 'End Time must be after Start Time', 'warning');
            return;
        }

        this.isModalLoading = true;
        try {
            await rescheduleMeeting({
                eventId: this.selectedMeeting.id,
                newStartDateTime: this.rescheduleForm.startDateTime,
                newEndDateTime: this.rescheduleForm.endDateTime
            });

            this.showToast('Rescheduled', 'Meeting time shifted & synced on Google Calendar!', 'success');
            this.closeRescheduleModal();
            await this.loadMeetings();
        } catch (error) {
            this.showToast('Reschedule Failed', this.reduceErrors(error), 'error');
        } finally {
            this.isModalLoading = false;
        }
    }

    // =========================================================
    // CANCEL MODAL HANDLERS
    // =========================================================

    openCancelConfirmModal(event) {
        const meetingId = event.target.dataset.id;
        const meeting = this.meetings.find(m => m.id === meetingId);
        if (!meeting) return;

        this.selectedMeeting = meeting;
        this.isCancelModalOpen = true;
    }

    closeCancelModal() {
        this.isCancelModalOpen = false;
    }

    async handleCancelSubmit() {
        this.isModalLoading = true;
        try {
            await cancelMeeting({ eventId: this.selectedMeeting.id });
            this.showToast('Cancelled', 'Meeting cancelled & removed from Google Calendar', 'success');
            this.closeCancelModal();
            await this.loadMeetings();
        } catch (error) {
            this.showToast('Cancellation Failed', this.reduceErrors(error), 'error');
        } finally {
            this.isModalLoading = false;
        }
    }

    // =========================================================
    // UTILITIES
    // =========================================================

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        if (!error) return 'Unknown error';
        if (typeof error === 'string') return error;
        if (error.body && typeof error.body.message === 'string') return error.body.message;
        if (error.message) return error.message;
        return JSON.stringify(error);
    }
}
