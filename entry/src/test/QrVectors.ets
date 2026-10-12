/*******************************************************************************
 *                                                                             *
 *  Copyright (C) 2026 by Max Lv <max.c.lv@gmail.com>                          *
 *                                                                             *
 *  This program is free software: you can redistribute it and/or modify       *
 *  it under the terms of the GNU General Public License as published by       *
 *  the Free Software Foundation, either version 3 of the License, or          *
 *  (at your option) any later version.                                        *
 *                                                                             *
 *  This program is distributed in the hope that it will be useful,            *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of             *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
 *  GNU General Public License for more details.                               *
 *                                                                             *
 *  You should have received a copy of the GNU General Public License          *
 *  along with this program. If not, see <http://www.gnu.org/licenses/>.       *
 *                                                                             *
 *******************************************************************************/

/**
 * Golden QR matrices, produced by zxing 3.5.3 — the encoder
 * shadowsocks-android uses — through tools/qr-oracle/run.sh.
 *
 * Do not edit by hand: add a line to tools/qr-oracle/corpus.txt and
 * regenerate. Each row is one line of the module matrix, packed four
 * modules to a hex digit, x ascending, the last digit padded with
 * zeroes.
 */
export class QrVector {
  name: string;
  ec: number;
  version: number;
  mask: number;
  text: string;
  rows: string[];

  constructor(name: string, ec: number, version: number, mask: number,
              text: string, rows: string[]) {
    this.name = name;
    this.ec = ec;
    this.version = version;
    this.mask = mask;
    this.text = text;
    this.rows = rows;
  }
}

/**
 * A length at which the version changes, and what zxing makes of it.
 * This is how the versions whose matrices are too large to carry
 * around are still pinned.
 */
export class QrSizeEntry {
  ec: number;
  length: number;
  version: number;
  mask: number;
  digest: number;

  constructor(ec: number, length: number, version: number, mask: number,
              digest: number) {
    this.ec = ec;
    this.length = length;
    this.version = version;
    this.mask = mask;
    this.digest = digest;
  }
}

export const QR_VECTORS: QrVector[] = [
      new QrVector('numeric-l', 0, 1, 1, '0123456789012345678901234567890123456789', [
    'FED3F8', '82B208', 'BA32E8', 'BA32E8', 'BACAE8', '82D208', 'FEABF8', '008000', 'E6E798', 'A42740', '9A1820', 'B80440', 'EE2958', '00B2C0', 'FE6D58', '82C0A8', 'BA6250', 'BA4640', 'BA94D8', '828770', 'FEC3D8',
  ]),
      new QrVector('numeric-m', 1, 2, 5, '0123456789012345678901234567890123456789', [
    'FE53BF8', '82DEA08', 'BABD2E8', 'BA99AE8', 'BA48AE8', '8200208', 'FEAABF8', '0093000', '82F8670', 'D52D6E0', 'A7FF4F8', '10858B8', '222D048', 'A980F48', 'BB795F0', '8010348', '8A50FE8', '008E888', 'FE11AB8', '824C8C0', 'BA2BFC0', 'BA229C8', 'BA783E8', '8213438', 'FEC6F58',
  ]),
      new QrVector('alnum-l', 0, 1, 7, 'HELLO WORLD $%*+-./: 0123', [
    'FE2BF8', '82B208', 'BAEAE8', 'BA22E8', 'BABAE8', '82CA08', 'FEABF8', '00A800', 'D30BB0', 'FCEB08', '9BBB50', '2D3D38', 'EF55A8', '00AAB8', 'FEC328', '822750', 'BA5B60', 'BA9958', 'BA3548', '82E2C8', 'FED940',
  ]),
      new QrVector('alnum-h', 3, 3, 2, 'HELLO WORLD $%*+-./: 0123', [
    'FEF32BF8', '82D43208', 'BAD45AE8', 'BA68D2E8', 'BA5382E8', '828F3A08', 'FEAAABF8', '00E89800', '3AAF3F38', '95CC84C8', '7E7388F8', '4CC364B0', 'E6440AD0', '70E42148', 'DFCCF3E0', 'A06CF728', '4F815208', 'F15CADC8', '930EF0D8', '8CA57C10', 'AAFBFF88', '00F278E8', 'FE749AC8', '821AE880', 'BA80FFC0', 'BAB7B010', 'BAE21CD0', '824AD558', 'FE6C21F0',
  ]),
      new QrVector('byte-l-1', 0, 1, 3, 'a', [
    'FEBBF8', '823208', 'BAD2E8', 'BACAE8', 'BA92E8', '827A08', 'FEABF8', '001800', 'F2FCE8', 'E83E40', '87D068', 'C813E0', 'F7E920', '009240', 'FE1940', '8261B0', 'BA0F88', 'BAD3F0', 'BAAB00', '828528', 'FEC480',
  ]),
      new QrVector('byte-l-17', 0, 1, 3, 'aaaaaaaaaaaaaaaaa', [
    'FEC3F8', '824208', 'BAF2E8', 'BAEAE8', 'BA9AE8', '827208', 'FEABF8', '000000', 'F2A4E8', '8CA1A8', '772718', 'A871C0', 'DAAB00', '009AC0', 'FE51C0', '825C70', 'BA5068', 'BACC00', 'BABC60', '82A708', 'FE86A0',
  ]),
      new QrVector('byte-l-18', 0, 2, 7, 'aaaaaaaaaaaaaaaaaa', [
    'FE233F8', '82E1208', 'BA82AE8', 'BA4D2E8', 'BAEBAE8', '82A9A08', 'FEAABF8', '00B5800', 'D31ABB0', 'A9DCE58', '2F9EAD8', '24FD590', '4E32E08', '4196778', '9636768', '51D1100', 'CB2CFA8', '00AF8C8', 'FE9BAF8', '822A8B8', 'BA20F98', 'BAF21C0', 'BA200C8', '82E3880', 'FEA9E98',
  ]),
      new QrVector('byte-l-54', 0, 4, 2, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', [
    'FE41BD3F8', '82D82C208', 'BA7286AE8', 'BAD0C2AE8', 'BA2F3D2E8', '82A7AC208', 'FEAAAABF8', '000D06800', 'FBEB42D50', '6141BD228', '4B582C070', '08F286D70', '2250C2D80', '39EF3D228', '6B07AC070', '28ED06D70', '922B42D80', 'D4A1BD228', 'E7182C070', '453286D70', 'B6F042D80', 'D02F3D228', '9727AC070', 'A82D06D70', '8BEB42F80', '0080BC8A8', 'FED9ADAF0', '8213078E8', 'BAF142F90', 'BAAEBDDB8', 'BA87ACA60', '828D06060', 'FECB43D10',
  ]),
      new QrVector('byte-l-107', 0, 6, 4, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', [
    'FE83E17A3F8', '82C8D06B208', 'BA9D853E2E8', 'BA9B697A2E8', 'BA2E397A2E8', '82B6B06B208', 'FEAAAAAABF8', '0073E53E000', 'CE205E85978', '088FA17A3E8', '6F414F94E48', '992BE53E348', 'A77E3885C40', '8C64917A3E8', 'BEC0D794E48', '49EA7D3E348', 'EFD94E85C40', '6993E57A3E8', 'DE1F2994E48', 'F035833E348', '5E449285C40', '612E397A3E8', '7F794F94E48', 'E4B3E53E348', 'D7885E85C40', '3837A17A3E8', '77F94F94E48', '5453E53E348', 'F32E3885C40', 'C044937A3E8', '3B00D794E48', '002A7D3E340', 'EE194E85FC8', '0093E57B8E8', 'FE7F2995AC8', '82B5833F8C8', 'BAE49285FC0', 'BA0E397AC68', 'BA794F94448', '82D3E53EE58', 'FEA85E84CD0',
  ]),
      new QrVector('byte-l-135', 0, 7, 1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', [
    'FEF67F2ACBF8', '828895225208', 'BA323AF752E8', 'BA64CA555AE8', 'BAFCCFAABAE8', '82A168A20208', 'FEAAAAAAABF8', '00C438888000', 'E6EE9FAAB798', '90AC00D55508', 'DA5EF2DDCDA8', 'A5F4550880D0', 'CFBB2DAAB2D8', 'B86B20D55508', 'BAF0F2DDCDA8', 'A4B2550880D0', '5761EDAAB2D8', 'FD89C0D55508', 'AA5772DDCDA8', '9135D50880D0', '9FD32FAABFD8', 'C89B28D55888', 'EAC69ADDCAA8', 'D8C4288888D0', 'CFDE9FAAAFD8', '845C1A554508', '6A56F75DDAA8', '105C45089A50', '82F33AAAB758', '25933A554508', 'CA08F75DDAA8', 'E1C245089A50', 'C289FAAAB758', 'C561DA554508', '0ACF775DDAA8', '79A5C5089A58', '9B133FAABFC8', '00D328D55888', 'FE2E8ADDDAA8', '82C4388888D0', 'BA3E9FAABFD8', 'BA7C15554880', 'BAD6FDDDCAB0', '82DC48889540', 'FE932AAABDC8',
  ]),
      new QrVector('byte-l-140', 0, 7, 1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', [
    'FE8BCF2ACBF8', '82E915225208', 'BA7BBAF752E8', 'BA44CA555AE8', 'BABCCFAABAE8', '82FF08A20208', 'FEAAAAAAABF8', '008A58888000', 'E6E9BFAAB798', 'E829A0D55508', 'B26772DDCDA8', '7DBDD50880D0', '36AB2DAAB2D8', '2D5320D55508', '7736F2DDCDA8', '110C550880D0', '1A6EADAAB2D8', '944C20D55508', '9ECEF2DDCDA8', 'C444550880D0', 'DFF32FAABFD8', '28CB28D55888', '3AA0FADDCAA8', 'C8FA488888D0', '1FA9BFAAAFD8', '6981BA554508', '960F775DDAA8', '5065C5089A50', 'A2333AAAB758', '61133A554508', 'FA2EF75DDAA8', 'C06445089A50', '5F7EBAAAB758', '097C3A554508', '0B96F75DDAA8', '78FC45089A40', '9B133FAABFC0', '00B328D55888', 'FE68EADDDAA8', '8282588888D0', 'BA69FFAABFD8', 'BA4195554880', 'BAAF7DDDCAB0', '82E5C8889540', 'FEB32AAABDC8',
  ]),
      new QrVector('byte-l-231', 0, 10, 1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', [
    'FE8CCCAAAAAF3F8', '82F111222225208', 'BA1BBBF777772E8', 'BA6D455555552E8', 'BAA5C5FEAAA92E8', '82C909222222208', 'FEAAAAAAAAAABF8', '00945C230088000', 'E6B3333FA2AB798', '75C333150D55508', 'BB38E8BDA5DCDA8', '4822424E88880D0', '2A29714CAAAB2D8', 'D0E951175555508', '4F76EEBFDDDCDA8', '3D94444088880D0', '821B3342AAAB2D8', 'E8A3330D5555508', '2A16EEA5DDDCDA8', '68A4444888880D0', '2A07ABCAAAAB2D8', '7DFDA3F55555508', '97616F5DDDDCDA8', 'B083C5E870880D8', '9BC9336A5AAB2C8', 'F90B3314F155508', '1FFE8EFE7FDCFA8', '9898246288888D0', 'FAB1176AAAABAD8', '08F115635554888', '3FF4EEBFDDDDFA8', '1DF444028889A50', '5E2F3376AAAB758', '60E333355554508', '83A2EE8FDDDDAA8', '718244048889A50', 'F6A4BAEEAAAB758', 'E5D23A255554508', 'FAC4F68BDDDDAA0', '19065C030689A40', 'BBAD3377A4AB758', '088133350F54508', '8ACEE8EBA7DDAA8', 'D09A42228889A50', '76F97176AAAB758', '906951355554508', 'A69CEE8BDDDDAA8', 'F90A44028889A50', '0231337EAAABFD8', '008F33235555888', 'FE32EEABDDDDAA8', '8284442288888D0', 'BA3FABBEAAABFD8', 'BA71A3AF5554880', 'BAFF6F6DDDDCAB8', '82B9C5D67089540', 'FEC9333E5AABDC8',
  ]),
      new QrVector('byte-m-100', 1, 6, 1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', [
    'FE93E6663F8', '825D8888A08', 'BAB6DDDDAE8', 'BA5A06662E8', 'BA31C6662E8', '82D98888A08', 'FEAAAAAABF8', '002F2222000', 'A32F9999928', 'ED099999B08', 'EB0477776A8', '98A72222450', '2B339999B58', '29320999B08', '2704EF776A8', 'D8A73A22450', '3BAA0999B58', 'D4B3D999B08', '076497776A8', 'A05C4222450', '0F285F99B58', '81F79999B08', '1622F7776A8', 'B0582222440', '3EC81999B48', '81F11999B08', '8B0A77776A8', '0CED2222450', 'BBAE9199B58', '09F08199B08', 'C31B77776A8', '04EC2222450', 'FF3E1999FD8', '00F59D98888', 'FEE1F176AA8', '820D24238D0', 'BA5A7D99FD8', 'BA35B999488', 'BA83B777CA8', '822F0222940', 'FEBC7998BC8',
  ]),
      new QrVector('byte-q-100', 2, 8, 1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', [
    'FE2FCF9AACBF8', '820853A227A08', 'BA5FABE775AE8', 'BAD04B5D552E8', 'BA2FCFEAA82E8', '828A563222208', 'FEAAAAAAAABF8', '00C0562900000', '62179BE3BB340', '90CE691555508', 'EA8D7D2DDCDA8', 'C8928248880D0', '77F266C2AB2D8', '98B9B17555508', '96FD194DDCDA8', '40E5084EE80D0', '7FF036C4CB2D8', '58AC097775508', '56FA414FFCDA8', '4540B158880D0', '7FA6EE42AB2D8', '55F320F555508', '5FE3C3EDDCFA8', '48C1BE30888C0', '5AA6EEBAABAC8', '68F3223554888', '7FE3C7FDDDFA8', '6941B8A889A50', '5EA6EFAAAB758', '7073279554508', '7BC5865DDDAA8', 'F847DF6009A50', 'EFBFF8022B758', '20A77DACD4508', '7A5368445DAA8', 'C92714A889A50', '5FEFCECAAB758', '50D7665554508', '46165B1DDDAA8', '70665B6889A50', 'E3A54BEAABFD8', '00E0AA3115888', 'FE73BEBBBDAA8', '82715A28888D0', 'BA5CF3EAABFD8', 'BA08535554888', 'BAFABBDDDCAA8', '82F1508889540', 'FE5CF2AAABDC8',
  ]),
      new QrVector('byte-h-13', 3, 2, 1, 'aaaaaaaaaaaaa', [
    'FE0D3F8', '82F4A08', 'BA95AE8', 'BA912E8', 'BA8C2E8', '82F3A08', 'FEAABF8', '0073000', '27ACDF0', 'A805B08', '02A96A8', '5515450', 'BB7DB58', '399CB08', 'F2C8EA8', '0173C50', 'DF2EFD8', '00A8888', 'FECFAA8', '82B08D0', 'BA6BFC0', 'BA5B480', 'BAC7CB8', '8262940', 'FE6ABC8',
  ]),
      new QrVector('byte-h-100', 3, 10, 1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', [
    'FE5B3C1082AF3F8', '82F2C39F6A25208', 'BAE5015A01772E8', 'BACB7EDDEB552E8', 'BAFB1C3EC0A92E8', '82EAEBE34022208', 'FEAAAAAAAAAABF8', '0022F6A3A680000', '279421BE14A35F0', '602542BF4749508', '26D4743097C2DA8', '9502766D20880D0', '079540AA92AB2D8', 'DC2483A7C555508', '86D1762895DCDA8', '190072EA2088050', 'C795C33012AB258', 'D0200327C555488', 'CAD7F53215DCC28', '1103F1ECA0880D0', '8B9440B492AB2D8', '542483A1C555568', 'C6D1F2B115DCDC8', '190376EBA1080E0', '839248B613AB2F8', '5C248386C515550', 'CFCBECBE95BCFF8', '188B70E3D8088D0', '8A8E56AA43ABAD8', '58A695E28D54888', 'CFA394BE85DDFA8', '197B1089E089A50', 'B6C62ED07AAB758', '5D56ADEC8554508', 'F3F3DCBAC5DDAA8', '393B38AD8888A50', '967E16D01AAAF58', '4C8EB58CC955D08', 'C29BFCDAD3DCEA8', 'D9F378CDC097C50', 'E7DFB74812BD758', '1CAF55E4C956508', 'B3FADCCAFBDFAA8', '983339F5C689A50', '563F57C114AB758', 'BD6E35644F54508', 'A77CDAD3FFDDAA8', 'F837BF75C689A50', '023A56BF14ABFD8', '00E83123CF55888', 'FEFFDE2A7FDDAA8', '82B43AE3C2888D0', 'BA3952BF92ABFD8', 'BA6CB3CF4954880', 'BAF95A93FDDCAB8', '8232BFCC4069500', 'FE374A9A944BDA8',
  ]),
      new QrVector('latin1-l', 0, 1, 4, 'café crème', [
    'FE8BF8', '82D208', 'BAFAE8', 'BAAAE8', 'BA7AE8', '82AA08', 'FEABF8', '000000', 'CE0978', 'B46CB0', '2FE810', '611D18', '361418', '00F9F0', 'FE34F0', '82E428', 'BAAC10', 'BA4A98', 'BA6C80', '8299C0', 'FEB608',
  ]),
      new QrVector('utf8-l', 0, 1, 3, '节点 A', [
    'FECBF8', '824A08', 'BAAAE8', 'BA92E8', 'BAE2E8', '820208', 'FEABF8', '006000', 'F2A4E8', 'A5A840', '17A8E0', '3D2D30', 'BF71A0', '0086E8', 'FE6480', '825908', 'BA76E0', 'BAC520', 'BA9020', '82BAD0', 'FEDD20',
  ]),
      new QrVector('utf8-h', 3, 3, 1, '节点名称 A', [
    'FE57B3F8', '82D77208', 'BA9FE2E8', 'BAE47AE8', 'BA8F52E8', '82971208', 'FEAAABF8', '0046A000', '27AA65F0', '7112A408', 'EBB154C0', 'BC2AA000', '42583E78', 'E52D8360', '67C0D158', 'F90683B8', '836309F0', '348909C0', 'EBEC6D68', '10397F88', 'EE796FB0', '00E2D8B8', 'FEA43AE8', '82AE58A8', 'BA299FD0', 'BA626A90', 'BAE5A3F8', '823F1018', 'FE365B68',
  ]),
      new QrVector('ss-url-l', 0, 4, 3, 'ss://YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA@example.com:8388#My%20Server', [
    'FEC07FBF8', '8200E1A08', 'BA9EB12E8', 'BAD4C2AE8', 'BAF1F3AE8', '824814208', 'FEAAAABF8', '0052CB800', 'F281E84E8', '8043FB748', '1602E1328', 'ED1D99048', '1253475F8', '25B156960', 'DF08B2250', '456B052E8', '82958BE00', 'AD0DDE9C8', '833B4A240', '116848E10', 'BA5B74550', 'F4CA2A778', '133E8D378', '6585A2E48', '8F6FDAFC0', '00F9018F0', 'FE72F9AA0', '8251058E0', 'BA45B5FD8', 'BAA5C8CF0', 'BA8B09E30', '82E168A08', 'FEAB4E5C0',
  ]),
      new QrVector('ss-url-h', 3, 10, 2, 'ss://YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA@example.com:8388?plugin=obfs-local%3Bobfs%3Dtls#My%20Server', [
    'FEE14B56FD7B3F8', '829CB8E566F1208', 'BAA3F8B6419F2E8', 'BA50F4D184112E8', 'BA22167E00E92E8', '82B104236CB6208', 'FEAAAAAAAAAABF8', '00AE11A3D092800', '3A91E77FCD26738', 'C403CA22B133DD8', 'CF97435F8DC44B0', 'F5ACCBE482AAEF0', 'AF5315FEDC52358', 'AC99866E2829CD0', '8A163D795E11F30', '440380A9493D438', 'EF1782C86E44510', 'F894AFB50975848', 'E3F1CF872633370', '98B3B0A6A37CAE8', '7A245724D077558', '7445521AF56CC28', 'D7AB708C6A52A70', '51269B31375B920', 'E7FDEA40F683260', '24D025A3E5C8CA0', '4FB90B3EE6AEFD8', 'B891F9A209138E8', '9ABF15EB8692AD8', 'C88D99625DF0880', '7FDA79BE42AEFF0', 'CD177D3C71E1B38', 'DA447341C6161C0', '1155AC910961208', 'FF99D3AD4A530F0', '70D7B8C66FB0E70', 'B7F01FF5DA707E0', '898A70765778A28', 'EE1E7BA568B2730', 'B18981826EA40E0', '9F4AF4CB7B58B00', '902F71ECE72CA68', '4BD9DCF319D8970', 'F001A12711DF3F0', '7B14E6AE4470380', '045F1B757169478', 'A61255BA1501070', 'F945BC4471E9F30', '0272F9FFAC26FC0', '008D9B23F9F8880', 'FE24632B9DC7AF0', '821237A2562F8B0', 'BABA953ED611F80', 'BAABF5CEE9282C0', 'BAF74D1648A3A00', '8232C3A2523A4C0', 'FE59F5217B61330',
  ]),
];

export const QR_SIZE_ENTRIES: QrSizeEntry[] = [
  new QrSizeEntry(0, 1, 1, 3, 1505357639),
  new QrSizeEntry(0, 17, 1, 3, 1521912062),
  new QrSizeEntry(0, 18, 2, 7, 833714198),
  new QrSizeEntry(0, 32, 2, 3, 520980948),
  new QrSizeEntry(0, 33, 3, 0, 386446826),
  new QrSizeEntry(0, 53, 3, 0, 336678912),
  new QrSizeEntry(0, 54, 4, 2, 894129185),
  new QrSizeEntry(0, 78, 4, 7, 1063760351),
  new QrSizeEntry(0, 79, 5, 1, 1412005973),
  new QrSizeEntry(0, 106, 5, 1, 899389797),
  new QrSizeEntry(0, 107, 6, 4, 1184410085),
  new QrSizeEntry(0, 134, 6, 4, 1416937009),
  new QrSizeEntry(0, 135, 7, 1, 834456509),
  new QrSizeEntry(0, 154, 7, 1, 601417894),
  new QrSizeEntry(0, 155, 8, 1, 1409546067),
  new QrSizeEntry(0, 192, 8, 1, 1086673408),
  new QrSizeEntry(0, 193, 9, 1, 1059467042),
  new QrSizeEntry(0, 230, 9, 1, 105210606),
  new QrSizeEntry(0, 231, 10, 1, 1156535565),
  new QrSizeEntry(0, 271, 10, 1, 1924368721),
  new QrSizeEntry(0, 272, 11, 1, 2121769790),
  new QrSizeEntry(0, 321, 11, 1, 1909507182),
  new QrSizeEntry(0, 322, 12, 1, 2088440327),
  new QrSizeEntry(0, 367, 12, 1, 319883842),
  new QrSizeEntry(0, 368, 13, 1, 274468095),
  new QrSizeEntry(0, 425, 13, 1, 700570655),
  new QrSizeEntry(0, 426, 14, 2, 568165903),
  new QrSizeEntry(0, 458, 14, 1, 294308938),
  new QrSizeEntry(0, 459, 15, 2, 2120494980),
  new QrSizeEntry(0, 520, 15, 1, 1321202254),
  new QrSizeEntry(0, 521, 16, 1, 1460588720),
  new QrSizeEntry(0, 586, 16, 1, 1370817368),
  new QrSizeEntry(0, 587, 17, 1, 1968222943),
  new QrSizeEntry(0, 644, 17, 1, 1855951481),
  new QrSizeEntry(0, 645, 18, 2, 42427982),
  new QrSizeEntry(0, 718, 18, 1, 160463535),
  new QrSizeEntry(0, 719, 19, 1, 2145575763),
  new QrSizeEntry(0, 792, 19, 1, 1136532727),
  new QrSizeEntry(0, 793, 20, 1, 1312787952),
  new QrSizeEntry(0, 858, 20, 1, 1043983785),
  new QrSizeEntry(0, 859, 21, 1, 651066258),
  new QrSizeEntry(0, 929, 21, 1, 1240947910),
  new QrSizeEntry(0, 930, 22, 1, 1532086525),
  new QrSizeEntry(0, 1003, 22, 1, 1458484264),
  new QrSizeEntry(0, 1004, 23, 1, 1117310933),
  new QrSizeEntry(0, 1091, 23, 1, 711615211),
  new QrSizeEntry(0, 1092, 24, 1, 994950116),
  new QrSizeEntry(0, 1171, 24, 1, 11142794),
  new QrSizeEntry(0, 1172, 25, 4, 109643958),
  new QrSizeEntry(0, 1273, 25, 4, 1047641216),
  new QrSizeEntry(0, 1274, 26, 4, 658134588),
  new QrSizeEntry(0, 1367, 26, 1, 101486979),
  new QrSizeEntry(0, 1368, 27, 1, 2040387911),
  new QrSizeEntry(0, 1465, 27, 1, 1690173237),
  new QrSizeEntry(0, 1466, 28, 2, 665030005),
  new QrSizeEntry(0, 1528, 28, 2, 689747002),
  new QrSizeEntry(0, 1529, 29, 1, 801825984),
  new QrSizeEntry(0, 1628, 29, 1, 180642665),
  new QrSizeEntry(0, 1629, 30, 2, 1818858635),
  new QrSizeEntry(0, 1732, 30, 1, 1635206414),
  new QrSizeEntry(0, 1733, 31, 2, 1433987010),
  new QrSizeEntry(0, 1840, 31, 2, 35716055),
  new QrSizeEntry(0, 1841, 32, 2, 1739282872),
  new QrSizeEntry(0, 1952, 32, 2, 152519910),
  new QrSizeEntry(0, 1953, 33, 2, 1413857771),
  new QrSizeEntry(0, 2068, 33, 2, 1856230366),
  new QrSizeEntry(0, 2069, 34, 2, 1853014041),
  new QrSizeEntry(0, 2188, 34, 2, 295349605),
  new QrSizeEntry(0, 2189, 35, 1, 1501508661),
  new QrSizeEntry(0, 2303, 35, 1, 1768465854),
  new QrSizeEntry(0, 2304, 36, 1, 1271565294),
  new QrSizeEntry(0, 2431, 36, 1, 907593800),
  new QrSizeEntry(0, 2432, 37, 1, 105029629),
  new QrSizeEntry(0, 2563, 37, 1, 837157745),
  new QrSizeEntry(0, 2564, 38, 1, 1118440533),
  new QrSizeEntry(0, 2699, 38, 1, 721883272),
  new QrSizeEntry(0, 2700, 39, 1, 2052672858),
  new QrSizeEntry(0, 2809, 39, 1, 958374943),
  new QrSizeEntry(0, 2810, 40, 1, 407574236),
  new QrSizeEntry(1, 1, 1, 5, 1940443008),
  new QrSizeEntry(1, 14, 1, 2, 780874054),
  new QrSizeEntry(1, 15, 2, 2, 1464339206),
  new QrSizeEntry(1, 26, 2, 3, 690631690),
  new QrSizeEntry(1, 27, 3, 2, 1436609159),
  new QrSizeEntry(1, 42, 3, 0, 1023137001),
  new QrSizeEntry(1, 43, 4, 6, 1734081053),
  new QrSizeEntry(1, 62, 4, 1, 723262235),
  new QrSizeEntry(1, 63, 5, 4, 630849561),
  new QrSizeEntry(1, 84, 5, 1, 1117293990),
  new QrSizeEntry(1, 85, 6, 0, 820393529),
  new QrSizeEntry(1, 106, 6, 0, 1536045161),
  new QrSizeEntry(1, 107, 7, 1, 1111582202),
  new QrSizeEntry(1, 122, 7, 1, 331740961),
  new QrSizeEntry(1, 123, 8, 1, 501531321),
  new QrSizeEntry(1, 152, 8, 1, 1191095407),
  new QrSizeEntry(1, 153, 9, 1, 1319125092),
  new QrSizeEntry(1, 180, 9, 1, 345025334),
  new QrSizeEntry(1, 181, 10, 1, 2112954467),
  new QrSizeEntry(2, 1, 1, 0, 1614997039),
  new QrSizeEntry(2, 11, 1, 7, 2114481933),
  new QrSizeEntry(2, 12, 2, 6, 2054125745),
  new QrSizeEntry(2, 20, 2, 0, 1768607995),
  new QrSizeEntry(2, 21, 3, 6, 2104059462),
  new QrSizeEntry(2, 32, 3, 0, 958267817),
  new QrSizeEntry(2, 33, 4, 1, 1005655053),
  new QrSizeEntry(2, 46, 4, 7, 2058156020),
  new QrSizeEntry(2, 47, 5, 6, 23183978),
  new QrSizeEntry(2, 60, 5, 0, 2072457362),
  new QrSizeEntry(2, 61, 6, 6, 629197429),
  new QrSizeEntry(2, 74, 6, 4, 1608090303),
  new QrSizeEntry(2, 75, 7, 1, 2133396004),
  new QrSizeEntry(2, 86, 7, 1, 2035246088),
  new QrSizeEntry(2, 87, 8, 1, 758006527),
  new QrSizeEntry(2, 108, 8, 1, 91135478),
  new QrSizeEntry(2, 109, 9, 2, 1578356057),
  new QrSizeEntry(2, 130, 9, 2, 418929174),
  new QrSizeEntry(2, 131, 10, 1, 1890091603),
  new QrSizeEntry(3, 1, 1, 0, 781880568),
  new QrSizeEntry(3, 7, 1, 0, 1418245090),
  new QrSizeEntry(3, 8, 2, 0, 1718275718),
  new QrSizeEntry(3, 14, 2, 0, 1109250103),
  new QrSizeEntry(3, 15, 3, 3, 242711691),
  new QrSizeEntry(3, 24, 3, 1, 443205091),
  new QrSizeEntry(3, 25, 4, 2, 437550309),
  new QrSizeEntry(3, 34, 4, 6, 293805806),
  new QrSizeEntry(3, 35, 5, 1, 262239765),
  new QrSizeEntry(3, 44, 5, 6, 1258427245),
  new QrSizeEntry(3, 45, 6, 5, 373063016),
  new QrSizeEntry(3, 58, 6, 1, 631447266),
  new QrSizeEntry(3, 59, 7, 1, 223703832),
  new QrSizeEntry(3, 64, 7, 1, 37876684),
  new QrSizeEntry(3, 65, 8, 1, 1597696327),
  new QrSizeEntry(3, 84, 8, 1, 2105324127),
  new QrSizeEntry(3, 85, 9, 2, 1874747095),
  new QrSizeEntry(3, 98, 9, 2, 477507335),
  new QrSizeEntry(3, 99, 10, 1, 1127791081),
];
