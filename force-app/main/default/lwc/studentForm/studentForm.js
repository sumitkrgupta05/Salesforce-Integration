/**
 * @description A Lightning Web Component form for creating and editing Student__c records.
 * Uses the Lightning Data Service (LDS) wire framework underneath via the base `lightning-record-edit-form` component.
 * 
 * @see {@link https://developer.salesforce.com/docs/component-library/bundle/lightning-record-edit-form/documentation | Salesforce Developer Docs - lightning-record-edit-form}
 * @see {@link https://developer.salesforce.com/docs/component-library/bundle/lightning-input-field/documentation | Salesforce Developer Docs - lightning-input-field}
 * 
 * Key Features:
 * - Automatically respects field-level security (FLS) and sharing rules.
 * - Handles CRUD operations (inserts if recordId is blank, updates if recordId is provided).
 * - Fires standard toast notifications upon success or error.
 */
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import STUDENT_OBJECT from '@salesforce/schema/Student__c';

export default class StudentForm extends LightningElement {
    /**
     * @property {string} recordId - The current Student__c record ID automatically contextually injected when hosted on a Record Page.
     */
    @api recordId;

    /**
     * @property {string} objectApiName - The API name of the target SObject, bound to Student__c.
     */
    objectApiName = STUDENT_OBJECT;

    /**
     * Handles the onsuccess event dispatched by the lightning-record-edit-form component.
     * Displays a success toast message when the record is saved successfully.
     * 
     * @param {CustomEvent} event - The success event containing record details.
     */
    handleSuccess(event) {
        const toastEvent = new ShowToastEvent({
            title: 'Success',
            message: 'Student record saved successfully!',
            variant: 'success'
        });
        this.dispatchEvent(toastEvent);
    }

    /**
     * Handles the onerror event dispatched by the lightning-record-edit-form component.
     * Displays an error toast message when the save operation fails due to validation rules or database errors.
     * 
     * @param {CustomEvent} event - The error event containing validation/database error messages.
     */
    handleError(event) {
        const toastEvent = new ShowToastEvent({
            title: 'Error Saving Record',
            message: event.detail.detail || 'An error occurred while saving the student record.',
            variant: 'error'
        });
        this.dispatchEvent(toastEvent);
    }
}