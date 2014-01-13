rules:
  expirationDate:
    ".read": true

  family:
    ".read": true

  request:
    $request:
      ".write": "true"
      ".validate": "newData.hasChildren(['deviceUuid', 'requestType', 'timestamp', 'userAuthId'])"
      userAuthId:
        ".validate": "newData.val() == auth.provider + '-' + auth.id"

  message:
    user:
      auth:
        $auth:
          ".read": "$auth == auth.provider + '-' + auth.id"
          ".write": "$auth == auth.provider + '-' + auth.id"

  sitter:
    ".read": true

  user:
    auth:
      $auth:
        ".read": "$auth == auth.provider + '-' + auth.id"
