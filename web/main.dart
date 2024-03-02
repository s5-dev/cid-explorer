import 'dart:convert';
import 'dart:html';
import 'dart:js_util';
import 'package:cid_explorer/js.dart';
import 'package:convert/convert.dart';
import 'package:filesize/filesize.dart';
import 'package:http/http.dart';
// ignore: depend_on_referenced_packages
import 'package:lib5/constants.dart';
// ignore: depend_on_referenced_packages
import 'package:lib5/lib5.dart';
// ignore: depend_on_referenced_packages
import 'package:lib5/util.dart';
import 'package:mime/mime.dart';
import 'package:s5/s5.dart';
import 'package:timeago/timeago.dart' as timeago;

final resolverCIDElement = document.getElementById('resolverCID')!;
final staticCIDElement = document.getElementById('staticCID')!;
final hnsDomainElement = document.getElementById('hnsDomain')!;
final reverseLookupElement = document.getElementById('reverseLookup')!;

final resultElement = document.getElementById('output')!;

var subfiles = <String, Map>{};

final httpClient = Client();

const esc = HtmlEscape();

void hide(Element el) {
  el.style.display = 'none';
}

void show(Element el) {
  el.style.display = 'block';
}

late final S5 s5;
List<String> uris = [];
late final String debugHttpApiBaseUrl;

void main() async {
  final TextInputElement element =
      document.getElementById('mainInput')! as TextInputElement;
  var initialValue = window.location.hash;
  if (initialValue.startsWith('#')) initialValue = initialValue.substring(1);

  if (initialValue.startsWith('{')) {
    final data = jsonDecode(initialValue.replaceAll('%22', '"'));
    uris = data['uris']?.cast<String>() ?? <String>[];
    initialValue = data['cid'] ?? '';
  }

  s5 = await S5.create(
    initialPeers: uris.isEmpty
        ? [
            'wss://z2Das8aEF7oNoxkcrfvzerZ1iBPWfm6D7gy3hVE4ALGSpVB@node.sfive.net/s5/p2p',
            'wss://z2DdbxV4xyoqWck5pXXJdVzRnwQC6Gbv6o7xDvyZvzKUfuj@s5.vup.dev/s5/p2p',
            'wss://z2DWuWNZcdSyZLpXFK2uCU3haaWMXrDAgxzv17sDEMHstZb@s5.garden/s5/p2p',
          ]
        : uris,
    autoConnectToNewNodes: false,
  );
  debugHttpApiBaseUrl = uris.isEmpty
      ? 'https://s5.garden'
      : '${Uri.parse(uris.first).scheme.replaceFirst('ws', 'http')}://${Uri.parse(uris.first).host}';

  element.value = initialValue;

  checkText(initialValue);

  getChildren = allowInterop(getChildrenLocal);

  element.addEventListener('input', (event) {
    final value = element.value ?? '';
    if (uris.isEmpty) {
      window.location.hash = value;
    } else {
      window.location.hash = jsonEncode({'cid': value, 'uris': uris});
    }
    checkText(value);
  });
}

final multibasePrefixMap = {
  'b': 'base32, (rfc4648 case-insensitive - no padding)',
  'z': 'base58btc (base58 bitcoin)',
  'u': 'base64url (rfc4648 no padding)',
};

void checkText(String value) {
  hide(resolverCIDElement);
  hide(staticCIDElement);
  hide(hnsDomainElement);
  hide(reverseLookupElement);

  value = value.trim();

  if (value.isNotEmpty) {
    document.getElementById('tutorialCard')!.style.display = 'none';
  } else {
    document.getElementById('tutorialCard')!.style.display = '';
  }
  resultElement.setInnerHtml(
    '',
    validator: TrustedNodeValidator(),
  );

  try {
    if (value.startsWith('Qm')) {
      redirectToIpfs(value);
    }
    final parts = value.split('.');
    final firstPart = parts.first;
    final cid = CID.decode(firstPart);

    if (cid.type == 1) {
      redirectToIpfs(value);
    }

    if (parts.length == 2 && parts[1].isNotEmpty) {
      final href = 'https://s5.cx/$value';
      addCard(
        '''<h2>Media Type</h2>
        <div class="result">Extension: ${parts.last}</div>
        <div class="result">Media type: ${lookupMimeType(parts.last)}</div>
        <div class="result">Stream this file: <a href="$href">$href</a></div>
      ''',
      );
    }
    var html = '''<h2>Encoding</h2>
        <div class="result">${multibasePrefixMap[firstPart[0]]}</div>
      ''';
    if (firstPart[0] != 'z') {
      html += '<div class="result">base58: ${cid.toBase58()}</div>';
    }
    if (firstPart[0] != 'b') {
      html += '<div class="result">base32: ${cid.toBase32()}</div>';
    }
    if (firstPart[0] != 'u') {
      html += '<div class="result">base64url: ${cid.toBase64Url()}</div>';
    }
    addCard(
      html,
    );
    processCID(cid);
  } catch (e) {
    print(e);
  }
}

void addCard(String content) {
  resultElement.appendHtml(
    ''' <div class="card">
      $content
    </div>''',
    validator: TrustedNodeValidator(),
  );
}

void redirectToIpfs(String cid) {
  window.location.replace('https://cid.ipfs.tech/#$cid');
}

void processCID(CID cid) async {
  if (cid.type == cidTypeResolver) {
    addCard('''
    <h2>Resolver CID</h2>
    <div class="result">Public Key Type: ${cid.hash.functionType == mkeyEd25519 ? 'Ed25519 (0xed)' : 'Unknown (${cid.hash.functionType})'}</div>
    <div class="result">Public Key: ${hex.encode(cid.hash.hashBytes)}</div>
    ''');

    final res = await s5.api.registryGet(cid.hash.fullBytes);

    addCard('''
    <h2>Registry Entry</h2>
    <div class="result">Revision: ${res?.revision}</div>
    <div class="result">Data: ${res == null ? null : hex.encode(res.data)}</div>

    ''');
    if (res != null && res.data[0] == registryS5CIDByte) {
      final cid = CID.fromBytes(res.data.sublist(1));
      addCard('''
    <h2>Registry Entry contains S5 CID</h2>
    <div class="result"><a href="#$cid" target="_blank">$cid</a></div>

    ''');
      processStaticCID(cid, false);
    }
  } else {
    processStaticCID(cid, true);
  }
}

String renderCIDDetails(CID cid) {
  return 'TODO';
}

String createLinkElement(String url) {
  return '<a href="$url" target="_blank">$url</a>';
}

void processStaticCID(CID cid, [bool doReverseLookup = false]) async {
  if (cid.type == cidTypeRaw) {
    addCard('''
<h2>Raw CID</h2>
<div class="result">Size: ${filesize(cid.size)} (${cid.size} bytes)</div>
''');
    processMultihash(cid.hash);
    fetchDownloadUris(cid.hash);
  } else if (cid.type == cidTypeMetadataWebApp) {
    final href = 'https://${cid.toBase32()}.s5.cx/';
    addCard('''
<h2>Web App Metadata CID</h2>
''');
// TODO <div class="result">Visit web app: <a href="$href">$href</div>
    final metadata = await s5.api.downloadMetadata(cid) as WebAppMetadata;

    addCard('''
<h2>Web App Metadata</h2>
<pre>
<code class="language-json">
${JsonEncoder.withIndent('  ').convert(metadata)};
</code>
</pre>
''');
    highlightAll();

    processMultihash(cid.hash);
    await fetchDownloadUris(cid.hash);
  } else if (cid.type == cidTypeMetadataMedia) {
    final href = 'https://tube5.app/#view/${cid.toBase58()}';
    addCard('''
<h2>Media Metadata CID</h2>
<div class="result">View this video: <a href="$href">$href</div>
''');
    // TODO final metadata = await s5ApiProvider.getMetadataByCID(cid) as MediaMetadata;

    final res = await httpClient
        .get(Uri.parse('$debugHttpApiBaseUrl/s5/metadata/$cid'));

    addCard('''
<h2>Media Metadata</h2>
<pre>
<code class="language-json">
${JsonEncoder.withIndent('  ').convert(json.decode(res.body))};
</code>
</pre>
''');
    highlightAll();

    processMultihash(cid.hash);
    await fetchDownloadUris(cid.hash);
  } else if (cid.type == 0x5d) {
    final href = 'https://tube5.app/#view/${cid.toBase58()}';

    // TODO final metadata = await s5ApiProvider.getMetadataByCID(cid) as MediaMetadata;

    final res = await httpClient
        .get(Uri.parse('$debugHttpApiBaseUrl/s5/metadata/$cid'));
    final meta = json.decode(res.body);

    addCard('''
<h2>Directory Metadata</h2>
<pre>
<code class="language-json">
${JsonEncoder.withIndent('  ').convert(meta)};
</code>
</pre>
''');
    highlightAll();

    var subdirs = '';

    for (final dir in meta['directories'].keys) {
      final publicKey =
          base64UrlNoPaddingDecode(meta['directories'][dir]['publicKey']);
      final cid = CID(cidTypeResolver, Multihash(publicKey));
      subdirs += '''
<li>$dir: <a href="#$cid" target="_blank">$cid</a></li>
''';
    }

    addCard('''
<h2>Subdirectories</h2>
<ul>
$subdirs
</ul>
''');

    processMultihash(cid.hash);
    await fetchDownloadUris(cid.hash);
  }
}

void processMultihash(Multihash hash) {
  addCard('''
<h2>Multihash</h2>
<div class="result">Type: ${hash.functionType == mhashBlake3Default ? 'BLAKE3 256-bits (0x1f)' : 'Unknown (${hash.functionType})'}</div>
<div class="result">Hash: ${hex.encode(hash.hashBytes)}</div>
''');
}

final storageLocationTypes = {
  0: 'Archive',
  3: 'File',
  5: 'Full',
  7: 'Bridge',
};

Future<List> fetchDebugStorageLocationsFromServer(Multihash hash) async {
  final res = await httpClient.get(
    Uri.parse(
      '$debugHttpApiBaseUrl/s5/debug/storage_locations/${hash.toBase64Url()}',
    ),
  );

  final List uris = json.decode(res.body)['locations'];

  uris.sort((a, b) => -a['score'].compareTo(b['score']));
  return uris;
}

Future<void> fetchDownloadUris(Multihash hash) async {
  final locations = await fetchDebugStorageLocationsFromServer(hash);

  var html = '''
<h2>Available Storage Locations</h2>
<pre>
''';
  for (final loc in locations) {
    final expiry = DateTime.fromMillisecondsSinceEpoch(loc['expiry'] * 1000);
    html += 'Type: ${storageLocationTypes[loc['type']]}\n';
    html += 'Parts: ${loc['parts']}\n';
    html += 'Expiry: ${timeago.format(expiry, allowFromNow: true)} ($expiry)\n';
    html += 'Node ID: ${loc['nodeId']}\n';
    html += 'Score (local): ${loc['score']}\n\n';
  }
  // html = html.trimRight();
  html += '// fetched from $debugHttpApiBaseUrl</pre>';

// <code class="language-lua"> </code>
  // addCard(html);
  highlightAll();
}

// TODO Implement
dynamic getChildrenLocal(String? id) {
  print('getChildrenLocal $id');

  id ??= '';
  final list = <Map>[];
  final level = id.split('/').length - 1;
/*  */
  final exisDirs = <String>[];

  bool isDirectory = subfiles.length > 1;

  for (final item in subfiles.values) {
    var filename = (item['filename'] as String);
    if (id.isNotEmpty) {
      if (!'$filename'.startsWith('$id/')) continue;
    }

    if (filename.startsWith('/')) {
      filename = filename.substring(1);
    }

    var subPath = '$filename'.substring(id.length);
    if (subPath.startsWith('/')) {
      subPath = subPath.substring(1);
    }

    if (subPath.contains('/')) {
      print(subPath);
      final dirName = subPath.split('/').first;
      print(dirName);
      if (exisDirs.contains(dirName)) continue;
      exisDirs.add(dirName);
      list.add(
        {
          'id': id.isEmpty ? dirName : (id + '/' + dirName),
          'label': dirName,
          'icon': {
            // TODO 'src': ${detectIcon(dirName, isDirectory: true)}.sv
          },
          'state': 'expanded'
        },
      );
      continue;
    }

    final basename = filename.split('/').last;

    String cidBaseHost = '';
    String currentStaticCID = '';

    list.add({
      'id': filename,
      'label': basename + ' (${filesize(item['len'])})',
      'link':
          isDirectory ? '${cidBaseHost}/$filename' : currentStaticCID,
      'icon': {
        // TODO 'src': ${detectIcon(basename, isDirectory: false)}.sv
      }
    });
  }

  return jsify(list);
}

class TrustedNodeValidator implements NodeValidator {
  @override
  bool allowsElement(Element element) => true;
  @override
  bool allowsAttribute(element, attributeName, value) => true;
}
