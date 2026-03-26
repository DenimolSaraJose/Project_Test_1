public without sharing class AccountHierarchyService {

    /**
     * Wrapper class to hold account data and its children for hierarchical representation
     */
    public class AccountWrapper implements Comparable {
        @AuraEnabled
        public Id id { get; set; }
        @AuraEnabled
        public Id parentId { get; set; }
        @AuraEnabled
        public Boolean isPartOfHierarchy { get; set; }
        @AuraEnabled
        public Id topLevelId { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String type { get; set; }
        @AuraEnabled
        public List<AccountWrapper> children { get; set; }
        @AuraEnabled
        public String membershipStatus { get; set; }
        @AuraEnabled
        public String accreditationStatus { get; set; }

        public AccountWrapper(Id id, Id parentId, Boolean isPartOfHierarchy, Id topLevelId, String name, String type, String membershipStatus, String accreditationStatus) {
            this.id = id;
            this.parentId = parentId;
            this.isPartOfHierarchy = isPartOfHierarchy;
            this.topLevelId = topLevelId;
            this.name = name;
            this.type = type;
            this.children = new List<AccountWrapper>();
            this.membershipStatus = membershipStatus;
            this.accreditationStatus = accreditationStatus;
        }

        // Implement the compareTo method to sort by name
        public Integer compareTo(Object compareTo) {
            AccountWrapper other = (AccountWrapper) compareTo;
            return this.name.compareTo(other.name);
        }
    }

    public class Parameter {
        @InvocableVariable(Label='Account Record Id' Description='' Required=true)
        public Id accountId;
    }

    public class ResultWrapper {
        @InvocableVariable
        public List<Account> accounts;
    }

    /**
     * Retrieves the AccountId of the currently logged-in user
     * @return The AccountId of the current user or null if not found
     */
    @AuraEnabled(Cacheable=true)
    public static String getUserAccountId() {
        User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return currentUser.AccountId;
    }

    @AuraEnabled
    public static Boolean isCommunity() {
        Id siteId = Site.getSiteId();
        if (siteId != null) {
            return true;
        }
        return false;
    }

    /**
     * Gets account hierarchies for a list of account IDs with optimized SOQL queries
     * @param accountIds List of account IDs to retrieve hierarchies for
     * @return A map where keys are account IDs and values are lists of AccountWrapper objects representing the hierarchy
     */
    @AuraEnabled
    public static Map<Id, List<AccountWrapper>> getAccountHierarchies(List<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Map<Id, List<AccountWrapper>>();
        }

        Set<Id> accountIdSet = new Set<Id>(accountIds);
        Map<Id, List<AccountWrapper>> hierarchyMap = new Map<Id, List<AccountWrapper>>();

        Map<Id, Account> accountMap = fetchAccountData(accountIdSet);
        Set<Id> topLevelAccountIds = findTopLevelAccounts(accountIdSet, accountMap);

        for (Id topLevelId : topLevelAccountIds) {
            Account rootAccount = accountMap.get(topLevelId);
            AccountWrapper rootWrapper = createAccountWrapper(rootAccount);
            buildHierarchyFromMap(topLevelId, rootWrapper, accountMap);

            for (Id inputAccountId : accountIdSet) {
                if (isAccountInHierarchy(inputAccountId, rootWrapper)) {
                    hierarchyMap.put(inputAccountId, new List<AccountWrapper>{
                            rootWrapper
                    });
                }
            }
        }

        return hierarchyMap;
    }

    /**
     * Checks if a specific account is part of the given hierarchy
     * @param accountId The account ID to check
     * @param hierarchyRoot The root of the hierarchy to search
     * @return Boolean indicating if the account is in the hierarchy
     */
    private static Boolean isAccountInHierarchy(Id accountId, AccountWrapper hierarchyRoot) {
        if (hierarchyRoot.id == accountId) {
            return true;
        }

        for (AccountWrapper child : hierarchyRoot.children) {
            if (isAccountInHierarchy(accountId, child)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Finds the root account using the pre-fetched account map
     * @param accountId The ID of the account to find the root for
     * @param accountMap Map of accounts to use for traversal
     * @return The root Account or null if not found
     */
    private static Account findRootAccount(Id accountId, Map<Id, Account> accountMap) {
        if (accountId == null || !accountMap.containsKey(accountId)) {
            return null;
        }

        Account currentAccount = accountMap.get(accountId);
        while (currentAccount.ParentId != null && accountMap.containsKey(currentAccount.ParentId)) {
            currentAccount = accountMap.get(currentAccount.ParentId);
        }
        return currentAccount;
    }

    /**
     * Builds the account hierarchy using the pre-fetched account map
     * @param rootAccountId The root Account record Id for the hierarchy, aka TopLevelAccount
     * @param accountWrapper The AccountWrapper to start building the hierarchy from
     * @param accountMap Map of accounts to use for building hierarchy
     */
    private static void buildHierarchyFromMap(Id rootAccountId, AccountWrapper accountWrapper, Map<Id, Account> accountMap) {
        if (accountWrapper == null) return;

        List<AccountWrapper> children = new List<AccountWrapper>();
        for (Account childAcc : accountMap.values()) {
            if (childAcc.ParentId == accountWrapper.id) {
                AccountWrapper childWrapper = createAccountWrapper(childAcc, rootAccountId);
                children.add(childWrapper);
            }
        }

        children.sort();
        accountWrapper.children.addAll(children);

        for (AccountWrapper childWrapper : children) {
            buildHierarchyFromMap(rootAccountId, childWrapper, accountMap);
        }
    }

//    /**
//     * Gets account hierarchies with direct mapping to Account objects
//     * @param accountIds Set of account IDs to retrieve hierarchies for
//     * @return A map where keys are account IDs and values are lists of Account objects representing the hierarchy
//     * @Deprecated 10-2-2026
//     */
//    public static Map<Id, List<Account>> getAccountHierarchies(Set<Id> accountIds) {
//        if (accountIds == null || accountIds.isEmpty()) {
//            return new Map<Id, List<Account>>();
//        }
//
//        Map<Id, List<AccountWrapper>> accountWrapperMap = getAccountHierarchies(new List<Id>(accountIds));
//        Map<Id, List<Account>> accountHierarchies = new Map<Id, List<Account>>();
//
//        for (Id accountId : accountIds) {
//            accountHierarchies.put(accountId, new List<Account>());
//
//            if (accountWrapperMap.containsKey(accountId)) {
//                List<AccountWrapper> wrappers = accountWrapperMap.get(accountId);
//                populateAccountHierarchy(accountHierarchies.get(accountId), wrappers);
//            }
//        }
//
//        return accountHierarchies;
//    }
//
//    /**
//     * Recursively populates an account hierarchy list with Account objects from AccountWrapper objects
//     * @param accountList The list to add accounts to
//     * @param wrappers The list of AccountWrapper objects to convert and add
//     * @Deprecated 10-2-2026
//     */
//    private static void populateAccountHierarchy(List<Account> accountList, List<AccountWrapper> wrappers) {
//        for (AccountWrapper wrapper : wrappers) {
//            Account account = createAccountFromWrapper(wrapper);
//            accountList.add(account);
//
//            if (!wrapper.children.isEmpty()) {
//                populateAccountHierarchy(accountList, wrapper.children);
//            }
//        }
//    }

    /**
     * Updates the TopLevelAccount__c field for a list of accounts
     * @param accounts List of accounts to update
     */
    public static void setOrUpdateTopLevelAccount(List<Account> accounts) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }

        Map<Id, Account> accountMap = new Map<Id, Account>(accounts);
        Map<Id, List<AccountWrapper>> hierarchyMap = getAccountHierarchies(new List<Id>(accountMap.keySet()));
        Map<Id, List<Account>> accountHierarchies = processHierarchy(hierarchyMap);
        Map<Id, Id> topLevelAccountIdByParentId = new Map<Id, Id>();
        List<Account> updateList = new List<Account>();

        for (Id accountId : accountMap.keySet()) {
            Account account = accountMap.get(accountId);
            if (accountHierarchies.containsKey(accountId)) {
                Map<Id, Account> hierarchyAccountMap = new Map<Id, Account>(accountHierarchies?.get(accountId));
                if (hierarchyAccountMap.containsKey(accountId)) {
                    Account accountToUpdate = hierarchyAccountMap.get(accountId);
                    if (accountToUpdate.ParentId != null) {
                        topLevelAccountIdByParentId.put(accountToUpdate.ParentId, accountToUpdate.TopLevelAccount__c);
                    }
                    if (account.TopLevelAccount__c == null || account.TopLevelAccount__c != accountToUpdate.TopLevelAccount__c ||
                            account.IsPartOfAccountHierarchy__c != accountToUpdate.IsPartOfAccountHierarchy__c) {
                        updateList.add(accountToUpdate);
                    }
                }
            }
        }
        if (!topLevelAccountIdByParentId.isEmpty()) {
            Set<Id> stagedAccountIds = new Map<Id, Account>(updateList).keySet();
            for (Account parentAccount : AccountSelector.getAccountsById(topLevelAccountIdByParentId.keySet())) {
                if (!parentAccount.IsPartOfAccountHierarchy__c && !stagedAccountIds.contains(parentAccount.Id)) {
                    updateList.add(new Account(
                            Id = parentAccount.Id,
                            IsPartOfAccountHierarchy__c = true,
                            TopLevelAccount__c = (parentAccount.ParentId != null) ? topLevelAccountIdByParentId.get(parentAccount.Id) : null
                    ));
                }
            }
        }

        if (!updateList.isEmpty()) {
            TriggerHandler.bypass('AccountTriggerHandler');
            Framework.Dispatcher.disableTriggerInContext.put('Account', true);
            Database.update(updateList, true);
        }
    }

    /**
     * Processes the entire hierarchy and converts all AccountWrapper objects to Account objects
     * @param hierarchyMap The map of account IDs to AccountWrapper lists
     * @return A map of account IDs to lists of Account objects representing the hierarchy
     */
    public static Map<Id, List<Account>> processHierarchy(Map<Id, List<AccountWrapper>> hierarchyMap) {
        Map<Id, List<Account>> accountHierarchies = new Map<Id, List<Account>>();

        for (Id accountId : hierarchyMap.keySet()) {
            List<AccountWrapper> wrappers = hierarchyMap.get(accountId);
            if (wrappers != null && !wrappers.isEmpty()) {
                List<Account> accounts = convertWrapperToAccount(wrappers.get(0));
                accountHierarchies.put(accountId, accounts);
            }
        }

        return accountHierarchies;
    }

    /**
     * Converts an AccountWrapper and its children to Account objects
     * @param wrapper The AccountWrapper to convert
     * @return A list of Account objects representing the hierarchy
     */
    public static List<Account> convertWrapperToAccount(AccountWrapper wrapper) {
        List<Account> accounts = new List<Account>();

        Account account = createAccountFromWrapper(wrapper);
        accounts.add(account);

        for (AccountWrapper childWrapper : wrapper.children) {
            accounts.addAll(convertWrapperToAccount(childWrapper));
        }

        return accounts;
    }

    /**
     * @description Retrieves a list of accounts in the hierarchy for a specified account ID.
     * This method is invocable and can be called from Salesforce Flows or Processes. It takes
     * a list of parameter objects containing account IDs, and returns all accounts
     * that are part of the hierarchy under the given account ID, including the account itself
     * and its ancestors and descendants.
     * @param parameters A list of Parameter objects, each containing an accountId to fetch
     * the corresponding hierarchy. The accountId should be a valid Account
     * record ID in the system.
     * @return List<Account> A collection of Account objects representing all accounts in the hierarchy
     * for the specified account Ids. If no accounts are found or if the accountId is invalid,
     * the method will return an empty list.
     */
    @InvocableMethod(Label='Get Accounts in hierarchy' Description='Returns a list of accounts in the hierarchy of the given account')
    public static List<ResultWrapper> getAccountsInHierarchy(List<Parameter> parameters) {
        ResultWrapper result = new ResultWrapper();
        result.accounts = new List<Account>();
        Set<Id> accountIdSet = new Set<Id>();
        for (Parameter param : parameters) {
            if (param.accountId != null) {
                accountIdSet.add(param.accountId);
            }
        }
        Map<Id, List<AccountWrapper>> hierarchyMap = getAccountHierarchies(new List<Id>(accountIdSet));
        for (Id accountId : accountIdSet) {
            if (hierarchyMap.containsKey(accountId)) {
                List<AccountWrapper> wrappers = hierarchyMap.get(accountId);
                List<Account> accountsInHierarchy = convertWrapperToAccount(wrappers.get(0));
                result.accounts.addAll(accountsInHierarchy);
            }
        }
        return new List<ResultWrapper>{result};
    }

    /**
     * Fetches account data from the database
     * @param accountIdSet Set of account IDs to fetch data for
     * @return A map of account IDs to Account objects
     */
    private static Map<Id, Account> fetchAccountData(Set<Id> accountIdSet) {
        Set<Id> parentIds = new Set<Id>();
        for (Account account : [
                SELECT Id
                        , Name
                        , Type
                        , ParentId
                        , IsPartOfAccountHierarchy__c
                        , TopLevelAccount__c
                        , Membership_Status2__c
                        , Accreditation_Status__c
                FROM Account
                WHERE ParentId != NULL
        ]) {
            parentIds.add(account.ParentId);
        }

        Map<Id, Account> accountMap = new Map<Id, Account>([
                SELECT Id, Name, Type, ParentId, IsPartOfAccountHierarchy__c, TopLevelAccount__c, Membership_Status2__c, Accreditation_Status__c, (SELECT Id, Name, Type, ParentId, IsPartOfAccountHierarchy__c, TopLevelAccount__c, Membership_Status2__c, Accreditation_Status__c FROM ChildAccounts)
                FROM Account
                WHERE Id IN :parentIds
                OR ParentId IN :parentIds
                ORDER BY Id
        ]);

        return accountMap;
    }

    /**
     * Finds top-level accounts for the given input accounts
     * @param accountIdSet Set of account IDs to find top-level accounts for
     * @param accountMap Map of accounts to use for traversal
     * @return A set of top-level account IDs
     */
    private static Set<Id> findTopLevelAccounts(Set<Id> accountIdSet, Map<Id, Account> accountMap) {
        Set<Id> topLevelAccountIds = new Set<Id>();
        for (Id accountId : accountIdSet) {
            Account rootAccount = findRootAccount(accountId, accountMap);
            if (rootAccount != null) {
                topLevelAccountIds.add(rootAccount.Id);
            }
        }
        return topLevelAccountIds;
    }

    /**
     * Creates an AccountWrapper object from an Account object
     * @param account The Account object to create the wrapper from
     * @return An AccountWrapper object
     */
    private static AccountWrapper createAccountWrapper(Account account) {
        return new AccountWrapper(
                account.Id,
                account.ParentId,
                true,
                account.TopLevelAccount__c,
                account.Name,
                account.Type,
                account.Membership_Status2__c,
                account.Accreditation_Status__c
        );
    }

    /**
     * Creates an AccountWrapper object from an Account object with a specified top-level ID
     * @param account The Account object to create the wrapper from
     * @param topLevelId The top-level account ID
     * @return An AccountWrapper object
     */
    private static AccountWrapper createAccountWrapper(Account account, Id topLevelId) {
        return new AccountWrapper(
                account.Id,
                account.ParentId,
                true,
                topLevelId,
                account.Name,
                account.Type,
                account.Membership_Status2__c,
                account.Accreditation_Status__c
        );
    }

    /**
     * Creates an Account object from an AccountWrapper object
     * @param wrapper The AccountWrapper object to create the Account from
     * @return An Account object
     */
    private static Account createAccountFromWrapper(AccountWrapper wrapper) {
        return new Account(
                Id = wrapper.id,
                Name = wrapper.name,
                Type = wrapper.type,
                ParentId = wrapper.parentId,
                IsPartOfAccountHierarchy__c = wrapper.isPartOfHierarchy,
                TopLevelAccount__c = wrapper.topLevelId
        );
    }
}