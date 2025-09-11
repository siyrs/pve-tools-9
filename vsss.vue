{
itemId: 'CPUW',
colspan: 2,
printBar: false,
title: gettext('CPU功耗'),
textField: 'cpupower',
renderer:function(value){
  const w0 = value.split('\n')[0].split(' ')[0];
  const w1 = value.split('\n')[1].split(' ')[0];
  return `CPU电源模式: <strong>${w0}</strong> | CPU功耗: <strong>${w1} W</strong> `
}
},