rules:
  expirationDate:
    ".read": true

  account:
    $provider:
      $id:
        ".read": "auth.provider == $provider && auth.id == $id"

  family:
    ".read": true

  request:
    $request:
      ".write": "true"
      ".validate": "newData.hasChildren(['accountKey']) || newData.hasChildren(['deviceUuid', 'requestType', 'timestamp', 'userAuthId'])"
      accountKey:
        ".validate": "newData.val() == auth.provider + '/' + auth.id"

      userAuthId:
        ".validate": "newData.val() == auth.provider + '-' + auth.id"

  message:
    user:
      auth:
        $auth:
          ".read": "$auth == auth.provider + '-' + auth.id"

    $provider:
      $id:
        ".read": "auth.provider == $provider && auth.id == $id"
        ".write": "auth.provider == $provider && auth.id == $id"

  sitter:
    ".read": true

  user:
    auth:
      $auth:
        ".read": "$auth == auth.provider + '-' + auth.id"
