import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import BLOOD_GROUP_FIELD from '@salesforce/schema/Contact.Blood_Group__c';
import DOB_FIELD from '@salesforce/schema/Contact.Date_of_Birth__c';
import HEIGHT_FIELD from '@salesforce/schema/Contact.Height_cm__c';
import WEIGHT_FIELD from '@salesforce/schema/Contact.Weight_kg__c';
import ALLERGIES_FIELD from '@salesforce/schema/Contact.Allergies__c';
import CHRONIC_CONDITIONS_FIELD from '@salesforce/schema/Contact.Chronic_Conditions__c';
import CURRENT_MEDICATIONS_FIELD from '@salesforce/schema/Contact.Current_Medications__c';
import LAST_CHECKUP_DATE_FIELD from '@salesforce/schema/Contact.Last_Health_Checkup_Date__c';
import HEALTH_INSURANCE_FIELD from '@salesforce/schema/Contact.Health_Insurance_Provider__c';

const FIELDS = [
    BLOOD_GROUP_FIELD,
    DOB_FIELD,
    HEIGHT_FIELD,
    WEIGHT_FIELD,
    ALLERGIES_FIELD,
    CHRONIC_CONDITIONS_FIELD,
    CURRENT_MEDICATIONS_FIELD,
    LAST_CHECKUP_DATE_FIELD,
    HEALTH_INSURANCE_FIELD
];

export default class ContactHealthSummary extends LightningElement {
    @api recordId;
    contactRecord;
    errorMessage;
    isLoading = true;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredContact({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.contactRecord = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.contactRecord = undefined;
        }
    }

    extractErrorMessage(error) {
        if (!error) {
            return 'An unknown error occurred while loading health information.';
        }
        if (typeof error === 'string') {
            return error;
        }
        if (error.body) {
            if (typeof error.body === 'string') {
                return error.body;
            }
            if (error.body.message) {
                return error.body.message;
            }
            if (Array.isArray(error.body)) {
                return error.body.map((e) => e.message).join(', ');
            }
        }
        if (error.message) {
            return error.message;
        }
        return JSON.stringify(error);
    }

    formatValue(val) {
        if (val === null || val === undefined) {
            return 'Not Available';
        }
        const str = String(val).trim();
        return str.length > 0 ? str : 'Not Available';
    }

    isAvailable(val) {
        if (val === null || val === undefined) {
            return false;
        }
        return String(val).trim().length > 0;
    }

    createFieldItem(key, label, rawVal) {
        const hasValue = this.isAvailable(rawVal);
        return {
            key,
            label,
            value: this.formatValue(rawVal),
            isFallback: !hasValue,
            valueClass: hasValue
                ? 'slds-text-body_regular slds-truncate'
                : 'slds-text-body_regular slds-truncate slds-text-color_weak empty-value'
        };
    }

    get column1Fields() {
        if (!this.contactRecord) {
            return [];
        }
        return [
            this.createFieldItem('bloodGroup', 'Blood Group', getFieldValue(this.contactRecord, BLOOD_GROUP_FIELD)),
            this.createFieldItem('dob', 'Date of Birth', getFieldValue(this.contactRecord, DOB_FIELD)),
            this.createFieldItem('height', 'Height (cm)', getFieldValue(this.contactRecord, HEIGHT_FIELD)),
            this.createFieldItem('allergies', 'Allergies', getFieldValue(this.contactRecord, ALLERGIES_FIELD)),
            this.createFieldItem('chronicConditions', 'Chronic Conditions', getFieldValue(this.contactRecord, CHRONIC_CONDITIONS_FIELD))
        ];
    }

    get column2Fields() {
        if (!this.contactRecord) {
            return [];
        }
        return [
            this.createFieldItem('weight', 'Weight (kg)', getFieldValue(this.contactRecord, WEIGHT_FIELD)),
            this.createFieldItem('lastCheckup', 'Last Health Checkup Date', getFieldValue(this.contactRecord, LAST_CHECKUP_DATE_FIELD)),
            this.createFieldItem('insurance', 'Health Insurance Provider', getFieldValue(this.contactRecord, HEALTH_INSURANCE_FIELD)),
            this.createFieldItem('currentMedications', 'Current Medications', getFieldValue(this.contactRecord, CURRENT_MEDICATIONS_FIELD))
        ];
    }

    get healthFields() {
        if (!this.contactRecord) {
            return [];
        }
        return [
            this.createFieldItem('bloodGroup', 'Blood Group', getFieldValue(this.contactRecord, BLOOD_GROUP_FIELD)),
            this.createFieldItem('weight', 'Weight (kg)', getFieldValue(this.contactRecord, WEIGHT_FIELD)),
            this.createFieldItem('dob', 'Date of Birth', getFieldValue(this.contactRecord, DOB_FIELD)),
            this.createFieldItem('lastCheckup', 'Last Health Checkup Date', getFieldValue(this.contactRecord, LAST_CHECKUP_DATE_FIELD)),
            this.createFieldItem('height', 'Height (cm)', getFieldValue(this.contactRecord, HEIGHT_FIELD)),
            this.createFieldItem('insurance', 'Health Insurance Provider', getFieldValue(this.contactRecord, HEALTH_INSURANCE_FIELD)),
            this.createFieldItem('allergies', 'Allergies', getFieldValue(this.contactRecord, ALLERGIES_FIELD)),
            this.createFieldItem('currentMedications', 'Current Medications', getFieldValue(this.contactRecord, CURRENT_MEDICATIONS_FIELD)),
            this.createFieldItem('chronicConditions', 'Chronic Conditions', getFieldValue(this.contactRecord, CHRONIC_CONDITIONS_FIELD))
        ];
    }

    get fields() {
        return this.healthFields;
    }
}
