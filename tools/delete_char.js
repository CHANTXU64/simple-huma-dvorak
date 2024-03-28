const fs = require('fs');

// 读取 common char 文件中的汉字
const wordFileName = 'tools/common_char.txt';
const wordContent = fs.readFileSync(wordFileName, 'utf-8').trim();

const match_table = JSON.parse(fs.readFileSync("tools/mapping_table.json"))

/** @param {string} x
/** @param {string} s
 *  @returns {string} */
function maps (s) {
  let res = "";
  for (let i = 0; i < s.length; ++i) {
    if (s[i] in match_table) {
      res += match_table[s[i]];
    } else {
      res += s[i];
    }
  }
  return res;
}

/**
 *  @param { string } fileName
 *  @returns { string[] } */
function getAllLines (fileName) {
  const fileContent = fs.readFileSync(fileName, 'utf-8');
  // 将 yaml 内容按行分割
  return fileContent.split('\n');
}

/** 处理 CSV 行，排除表头并保留首列第一个汉字在 word 文件中找得到的行
 *  @param { string } fileName
 *  @param { number } startRow
 *  @returns { string[] } */
function getFilteredLines (fileName, startRow) {
  const csvLines = getAllLines(fileName);
  // 记录被删除的行的首个汉字
  let deletedChineseCharacters = [];
  let filteredLines = csvLines.map((line, index) => {
    if (index <= startRow) {
      // 如果是表头行，直接返回
      return line;
    }
    const firstChineseCharacter = line.split('\t')[0];
    if (!wordContent.includes(firstChineseCharacter)) {
      // 记录被删除的行的首个汉字
      deletedChineseCharacters.push(firstChineseCharacter);
      return null; // 返回 null 表示删除这一行
    }
    return line;
  }).filter(line => line !== null); // 过滤掉被删除的行（为 null 的行）
  // 输出被删除的行的首个汉字
  console.log('被删除的:\n', deletedChineseCharacters.join(''));
  return filteredLines;
}

/**
 *  @param { string[] } lines
 *  @param { number } startRow
 *  @param { RegExp } searchRe
 *  @returns { string[] } */
function replaceCode (lines, startRow, searchRe) {
  return lines.map((line, index) => {
    if (index <= startRow) {
      return line;
    }
    let replaceStr = searchRe.exec(line);
    if (replaceStr == null) {
      return line;
    } else {
      return line.replace(searchRe, maps(replaceStr[0]));
    }
  });
}

/**
 *  @param { string[] } lines
 *  @param { number } startRow
 *  @param { RegExp } searchRe
 *  @returns { string[] } */
function replaceCodeAndExpand3Code (lines, startRow, searchRe) {
  // let charMap: Map<string, string[][]> = new Map();
  let charMap = new Map();
  lines.map((line, index) => {
    if (index > startRow) {
      let replaceStr = searchRe.exec(line);
      if (replaceStr != null) {
        let newLine = line.replace(searchRe, maps(replaceStr[0]));
        let splittedArray = newLine.split("\t");
        if (splittedArray.length == 3) {
          let char = splittedArray[0];
          let code = splittedArray[1];
          let num = splittedArray[2];
          let value = charMap.get(char);
          if (value == undefined) {
            charMap.set(char, [[code, num]]);
          } else {
            value.push([code, num]);
          }
        }
      }
    }
  });
  // let res: string[] = [];
  let res = [];
  for (let i = 0; i <= startRow; ++i) {
    res.push(lines[i]);
  }
  charMap.forEach((value, char) => {
    let codeMaxLength = 0;
    let code_3 = "";
    let num_3 = "";
    value.forEach(v => {
      res.push(char + "\t" + v[0] + "\t" + v[1]);
      codeMaxLength = Math.max(codeMaxLength, v[0].length);
      if (v[0].length == 3) {
        code_3 = v[0];
        num_3 = v[1];
      }
    });
    if (codeMaxLength == 3) {
      let code_4 = code_3 + code_3[2];
      let num_4 = num_3;
      res.push(char + "\t" + code_4 + "\t" + num_4);
    }
  });
  return res;
}

// 读取 orig yaml 文件
// 将过滤后的内容重新组合为字符串
let filteredLines = getFilteredLines('./orig.tiger.dict.yaml', 10);
let filteredCSVContent = replaceCodeAndExpand3Code(filteredLines, 10, /\t.*\t/).join('\n');
// 将过滤后的内容写入新的 yaml 文件
let filteredCSVFileName = './tiger.dict.yaml';
fs.writeFileSync(filteredCSVFileName, filteredCSVContent, 'utf-8');
console.log('过滤完成，结果已写入文件：', filteredCSVFileName);

// 读取 orig yaml 文件
// 将过滤后的内容重新组合为字符串
filteredLines = getFilteredLines('./orig.tigress.dict.yaml', 20);
filteredCSVContent = replaceCode(filteredLines, 20, /\s[a-z',.;\t]*$/g).join('\n');
// 将过滤后的内容写入新的 yaml 文件
filteredCSVFileName = './tigress.dict.yaml';
fs.writeFileSync(filteredCSVFileName, filteredCSVContent, 'utf-8');
console.log('过滤完成，结果已写入文件：', filteredCSVFileName);

// 读取 orig yaml 文件
// 将过滤后的内容重新组合为字符串
let allLines = getAllLines('./orig.tigress_ci.dict.yaml');
filteredCSVContent = replaceCode(allLines, 19, /\s[a-z',.;]+/g).join('\n');
// 将过滤后的内容写入新的 yaml 文件
filteredCSVFileName = './tigress_ci.dict.yaml';
fs.writeFileSync(filteredCSVFileName, filteredCSVContent, 'utf-8');
console.log('过滤完成，结果已写入文件：', filteredCSVFileName);

// 读取 orig yaml 文件
// 将过滤后的内容重新组合为字符串
allLines = getAllLines('./orig.tigress_simp_ci.dict.yaml');
filteredCSVContent = replaceCode(allLines, 19, /\s[a-z',.;]+/g).join('\n');
// 将过滤后的内容写入新的 yaml 文件
filteredCSVFileName = './tigress_simp_ci.dict.yaml';
fs.writeFileSync(filteredCSVFileName, filteredCSVContent, 'utf-8');
console.log('过滤完成，结果已写入文件：', filteredCSVFileName);

// 读取 orig yaml 文件
// 将过滤后的内容重新组合为字符串
filteredCSVContent = getFilteredLines('./orig.stroke.dict.yaml', 22).join('\n');
// 将过滤后的内容写入新的 yaml 文件
filteredCSVFileName = './stroke.dict.yaml';
fs.writeFileSync(filteredCSVFileName, filteredCSVContent, 'utf-8');
console.log('过滤完成，结果已写入文件：', filteredCSVFileName);

// 读取 orig yaml 文件
// 将过滤后的内容重新组合为字符串
filteredLines = getFilteredLines('opencc/orig.hu_cf.txt', -1);
filteredLines = replaceCode(filteredLines, -1, /(?<=·&nbsp;[a-z',.;]*&nbsp;)[a-z',.;]*〕/);
filteredLines  = replaceCode(filteredLines, -1, /(?<=·&nbsp;)[a-z',.;]*\&/);
filteredCSVContent = replaceCode(filteredLines, -1, /(?<=·&nbsp;)[a-z',.;]*〕/).join('\n');
// 将过滤后的内容写入新的 yaml 文件
filteredCSVFileName = 'opencc/hu_cf.txt';
fs.writeFileSync(filteredCSVFileName, filteredCSVContent, 'utf-8');
console.log('过滤完成，结果已写入文件：', filteredCSVFileName);
