const targets = [
  'https://gitee.com/openharmony/docs/raw/master/zh-cn/application-dev/file-management/save-user-file.md',
  'https://gitee.com/openharmony/docs/raw/master/zh-cn/application-dev/security/AccessToken/savebutton.md'
];
for (const u of targets) {
  try {
    const res = await fetch(u);
    const text = await res.text();
    console.log('=== ' + u + ' status ' + res.status + ' ===');
    console.log(text.substring(0, 8000));
  } catch (e) {
    console.log('ERR ' + u + ': ' + e.message);
  }
}
