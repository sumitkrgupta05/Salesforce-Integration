public with sharing class ReactExperienceController {
    @AuraEnabled(cacheable=true)
    public static List<Account> getSampleAccounts() {
        try {
            return [SELECT Id, Name FROM Account WITH USER_MODE LIMIT 5];
        } catch (Exception e) {
            return new List<Account>();
        }
    }
}
