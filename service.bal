import ballerina/http;
import ballerina/regex;

//SCIM module.
import ballerinax/scim;

configurable string asgardeoOrg = ?;
configurable string clientId = ?;
configurable string clientSecret = ?;

configurable string[] scope = [
    "internal_user_mgt_view",
    "internal_user_mgt_list",
    "internal_user_mgt_create",
    "internal_user_mgt_delete",
    "internal_user_mgt_update",
    "internal_user_mgt_delete",
    "internal_group_mgt_view",
    "internal_group_mgt_list",
    "internal_group_mgt_create",
    "internal_group_mgt_delete",
    "internal_group_mgt_update",
    "internal_group_mgt_delete"
];

//Create a SCIM connector configuration
scim:ConnectorConfig scimConfig = {
    orgName: asgardeoOrg,
    clientId: clientId,
    clientSecret: clientSecret,
    scope: scope
};

scim:Client scimClient = check new (scimConfig);

type createUserRequest record {
    string password;
    string email;
    string name;
};

string studentGroupId="8da72e16-f48d-4ec4-adab-66c2ec6940b4";
string commerceGroupId="6a0332be-16f3-48c8-95df-aff5681fa02e";
string artsGroupId="81af19d1-ac9e-443e-9e62-603c25501a06";
string scienceGroupId="6569a789-d829-4075-9fae-1dfe13d78189";

# Description
#
# + email - Parameter Description
# + return - Return Value Description
function findUserGroup(string email) returns string|error {
    
    if regex:matches(email, "[A-Za-z0-9]+@com\\.greenville\\.edu") {
        return commerceGroupId;
    }   
    if regex:matches(email, "[A-Za-z0-9]+@sci\\.greenville\\.edu") {
        return scienceGroupId;
    }   
    if regex:matches(email, "[A-Za-z0-9]+@arts\\.greenville\\.edu") {
        return artsGroupId;
    }   
        if regex:matches(email, "[0-9]+[A-Za-z]+@greenville\\.edu") {
        return studentGroupId;
    }   

    return error("could not identify group");
}

# Description
#
# + userId - Parameter Description
# + return - Return Value Description
function deleteUser(string userId) returns error? {

    scim:ErrorResponse|error? deleteUserResponse = scimClient->deleteUser(userId);

    if (deleteUserResponse is error) {
        return error("could not delete user");
    }
}

function findUserByEmail(string email) returns error|scim:UserResource {

    string properUserName = string `DEFAULT/${email}`;

    scim:UserSearch searchData = {filter: string `userName eq ${properUserName}`};
    scim:UserResponse|scim:ErrorResponse|error searchResponse = check scimClient->searchUser(searchData);
    
    if searchResponse is scim:UserResponse {
        scim:UserResource[] userResources = searchResponse.Resources ?: [];

        return userResources[0];
    } 
    
    return error("error occurred while searching the user");
}

# A service representing a network-accessible API
# bound to port `9090`.
service / on new http:Listener(9090) {

    # Description
    # This API responds with the per group head count. 
    # 
    # + return - Json searchResponse with the count of members in each group.
    resource function get groupMemberCount() returns json|error {

        int studentCount = 0;
        int commerceCount = 0;
        int artCount = 0;
        int scienceCount = 0;
        
        //Get the group resources of each required group using the getGroup method. 
        scim:GroupResource studentGroup = check scimClient->getGroup(studentGroupId);
        scim:GroupResource commerceGroup = check scimClient->getGroup(commerceGroupId);
        scim:GroupResource artGroup = check scimClient->getGroup(artsGroupId);
        scim:GroupResource scienceGroup = check scimClient->getGroup(scienceGroupId);

        //find the member count in each group.
        if studentGroup.members != () {
            studentCount = (<scim:Member[]> studentGroup.members).length();
        }
        if commerceGroup.members != () {
            commerceCount = (<scim:Member[]> commerceGroup.members).length();
        }
        if artGroup.members != () {
            artCount = (<scim:Member[]> artGroup.members).length();
        }
        if scienceGroup.members != () {
            scienceCount = (<scim:Member[]> scienceGroup.members).length();
        }
        
        //Create searchResponse
        json searchResponse=  {
            totalStudentCount: studentCount,
            teacherCount: {
                commerce: commerceCount,
                arts: artCount,
                science: scienceCount
            }
        };

        return searchResponse;
    }

    resource function post createUserAccount(@http:Payload createUserRequest payload) returns http:Created|error|http:BadRequest {
        
        string|error userGroupId = findUserGroup(payload.email);
        
        if userGroupId is error {
            return http:BAD_REQUEST;
        }

        scim:UserCreate user = {
            password: payload.password,
            userName: string `DEFAULT/${payload.email}`
        };
        
        scim:UserResource|scim:ErrorResponse|error createdUser = check scimClient->createUser(user);

        if createdUser is error {
            return error("error occurred while creating user");
        }

        if !(createdUser.id is string) {
            return error("error occurred while creating user");
        }

        string createdUserId = <string>createdUser.id;

        scim:GroupPatch Group = {Operations: [{op: "add", value: {members: [{"value": createdUserId, "display": user.userName}]}}]};
        scim:GroupResponse|scim:ErrorResponse|error groupResponse = check scimClient->patchGroup( userGroupId, Group);

        if groupResponse is error|scim:ErrorResponse {
            //since the API operations are atomic, we need to delete the created user since the user coudn't be applied to proper group. 
            error? userDeleteError = deleteUser(createdUserId);

            if userDeleteError is error {
                return error("error occurred while adding user to group. user could not be deleted");
            }

            return error("error occurred while craeating user");
        }

        return http:CREATED;
    }


    resource function delete deleteUser(string email)  returns  error|http:STATUS_NO_CONTENT {
        
        error|scim:UserResource searchResponse = findUserByEmail(email);

        if searchResponse is error {
            
            return error("error occurred while searching the user");
        }

        string userId = <string>searchResponse.id;

         if userId == "" {
            
            return error("error occurred while searching the user");
        }

        scim:ErrorResponse|error? deleteResponse = check scimClient->deleteUser(userId);

        if deleteResponse is error {

            return error("error occurred while deleting the user");
        }

        return http:STATUS_NO_CONTENT;

    }

    resource function get searchUserProfile(string email) returns json|error {
        
        error|scim:UserResource searchResponse = findUserByEmail(email);
        
        if searchResponse is error {
            return error("error in searching user profile");
        }

        return {
            firstName: searchResponse.name?.givenName,
            lastName: searchResponse.name?.familyName,
            displayName: searchResponse.displayName,
            userName: searchResponse.userName
        };
    }




}


