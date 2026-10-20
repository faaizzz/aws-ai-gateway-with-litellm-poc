// CloudFront Function (viewer-request, runtime 2.0): HTTP basic auth.
// __USER__ and __PASSWORD_SHA256__ are filled in by Terraform. Only the
// password's SHA-256 is embedded, never the password.
import crypto from 'crypto';

function unauthorized() {
  return {
    statusCode: 401,
    statusDescription: 'Unauthorized',
    headers: {
      'www-authenticate': { value: 'Basic realm="AI Gateway PoC docs", charset="UTF-8"' },
      'cache-control': { value: 'no-store' },
    },
  };
}

function handler(event) {
  var request = event.request;
  var header = request.headers.authorization;
  if (!header || header.value.indexOf('Basic ') !== 0) {
    return unauthorized();
  }
  var decoded = Buffer.from(header.value.substring(6), 'base64').toString('utf8');
  var sep = decoded.indexOf(':');
  if (sep < 0) {
    return unauthorized();
  }
  var user = decoded.substring(0, sep);
  var hash = crypto.createHash('sha256').update(decoded.substring(sep + 1)).digest('hex');
  if (user !== '__USER__' || hash !== '__PASSWORD_SHA256__') {
    return unauthorized();
  }
  return request;
}
