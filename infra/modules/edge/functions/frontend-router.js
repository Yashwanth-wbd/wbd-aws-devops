// Viewer-request function for the frontend (cloudfront-js-2.0).
// Serves /releases/<current_release>/... from S3; app routes without a file extension get index.html.
// frontend-ci.yml switches releases by changing the current_release key; no distribution change.
import cf from 'cloudfront';

const kvs = cf.kvs('${kvs_id}');

async function handler(event) {
  const request = event.request;
  let release = '${initial_release}';
  try {
    release = await kvs.get('current_release');
  } catch (err) {
    // key missing: keep the initial release
  }

  let uri = request.uri;
  const last = uri.substring(uri.lastIndexOf('/') + 1);
  if (last === '' || last.indexOf('.') === -1) {
    uri = '/index.html';
  }

  request.uri = '/releases/' + release + uri;
  return request;
}
