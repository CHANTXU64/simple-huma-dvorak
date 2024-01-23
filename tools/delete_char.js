const fs = require('fs');

// 读取 common char 文件中的汉字
const wordFileName = 'tools/common_char.txt';
const wordContent = fs.readFileSync(wordFileName, 'utf-8').trim();

// 读取 orig yaml 文件
const csvFileName = './orig.tiger.dict.yaml';
const csvContent = fs.readFileSync(csvFileName, 'utf-8');

// 将 yaml 内容按行分割
const csvLines = csvContent.split('\n');

// 记录被删除的行的首个汉字
const deletedChineseCharacters = [];

// 处理 CSV 行，排除表头并保留首列第一个汉字在 word 文件中找得到的行
const filteredLines = csvLines.map((line, index) => {
  if (index === 0 || index === 1 || index === 2 || index === 3 || index === 4 || index === 5 || index === 6 || index === 7 || index === 8 || index === 9 || index === 10) {
    // 如果是表头行，直接返回
    return line;
  }

  const firstChineseCharacter = line.split('\t')[0];
  // const firstChineseCharacter = line.trim().charAt(0);
  if (!wordContent.includes(firstChineseCharacter)) {
    // 记录被删除的行的首个汉字
    deletedChineseCharacters.push(firstChineseCharacter);
    return null; // 返回 null 表示删除这一行
  }
  return line;
}).filter(line => line !== null); // 过滤掉被删除的行（为 null 的行）

// 将过滤后的内容重新组合为字符串
const filteredCSVContent = filteredLines.join('\n');

// 输出被删除的行的首个汉字
console.log('被删除的:\n', deletedChineseCharacters.join(''));

// 将过滤后的内容写入新的 yaml 文件
const filteredCSVFileName = './tiger.dict.yaml';
fs.writeFileSync(filteredCSVFileName, filteredCSVContent, 'utf-8');

console.log('过滤完成，结果已写入文件：', filteredCSVFileName);

