global with sharing class LearnDCMCPAccountAction {

    global class AccountRequest {
        @InvocableVariable(label='Account Name or ID' description='The name or Salesforce record ID of the Account to retrieve.' required=true)
        global String accountIdentifier;
    }

    global class AccountResult {
        @InvocableVariable(label='Is Found' description='True if the account was located in Salesforce.')
        global Boolean isFound;

        @InvocableVariable(label='Account ID' description='Salesforce Record ID of the Account.')
        global String accountId;

        @InvocableVariable(label='Account Name' description='Full name of the Account.')
        global String accountName;

        @InvocableVariable(label='CSM Email' description='Email of the assigned Customer Success Manager (Account.CSM_Email__c).')
        global String csmEmail;

        @InvocableVariable(label='Industry' description='Industry classification of the Account.')
        global String industry;

        @InvocableVariable(label='Primary Contact Name' description='Name of the primary contact.')
        global String primaryContactName;

        @InvocableVariable(label='Primary Contact Email' description='Email address of the primary contact.')
        global String primaryContactEmail;

        @InvocableVariable(label='Contact List Summary' description='Summary list of contacts associated with this Account.')
        global String contactSummary;
    }

    @InvocableMethod(
        label='Get Account CRM Details'
        description='Retrieves live Account details, assigned CSM email, industry, and associated contacts from Salesforce.'
    )
    global static List<AccountResult> getAccountDetails(List<AccountRequest> requests) {
        List<AccountResult> results = new List<AccountResult>();

        for (AccountRequest req : requests) {
            AccountResult res = new AccountResult();
            res.isFound = false;

            if (String.isBlank(req.accountIdentifier)) {
                results.add(res);
                continue;
            }

            String searchPattern = '%' + req.accountIdentifier.trim() + '%';
            List<Account> accList = [
                SELECT Id, Name, CSM_Email__c, Industry,
                       (SELECT Id, Name, Email, Title FROM Contacts LIMIT 5)
                FROM Account
                WHERE Name LIKE :searchPattern OR Id = :req.accountIdentifier.trim()
                LIMIT 1
            ];

            if (!accList.isEmpty()) {
                Account acc = accList[0];
                res.isFound = true;
                res.accountId = acc.Id;
                res.accountName = acc.Name;
                res.csmEmail = acc.CSM_Email__c;
                res.industry = acc.Industry;

                List<String> contactLines = new List<String>();
                if (acc.Contacts != null && !acc.Contacts.isEmpty()) {
                    res.primaryContactName = acc.Contacts[0].Name;
                    res.primaryContactEmail = acc.Contacts[0].Email;

                    for (Contact c : acc.Contacts) {
                        contactLines.add(c.Name + (String.isNotBlank(c.Title) ? ' (' + c.Title + ')' : '') + ': ' + (String.isNotBlank(c.Email) ? c.Email : 'No Email'));
                    }
                }
                res.contactSummary = String.join(contactLines, ' | ');
            }

            results.add(res);
        }

        return results;
    }
}
