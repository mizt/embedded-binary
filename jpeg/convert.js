const fs = require("fs");

const className = "EmbeddedJPEG";
const binary = fs.readFileSync("./sample.jpg");
const dst = "./";

let uint = (((binary.length+3)>>2)<<2);
let diff = uint - binary.length;

let arr = [];
for(let k=0; k<binary.length; k++) arr.push(binary[k]);
for(let k=0; k<diff; k++) arr.push(0);
 
let str = "";
for(let k=0; k<(arr.length)>>2; k++) {
	str += "0x"+((arr[k*4+3]<<24|arr[k*4+2]<<16|arr[k*4+1]<<8|arr[k*4+0])>>>0).toString(16).toUpperCase()+",";
}

var h = "class "+className+" {\n"
h += "\tprivate:\n";
h += "\t\t"+className+"();\n"
h += "\t\tvoid operator=(const "+className+" &o) {}\n"
h +="\t\t"+className+"(const "+className+" &o) {}\n"
h += "\tpublic:\n";
h += "\t\tunsigned char *bytes = nullptr;\n";
h += "\t\tconst unsigned int length = "+binary.length+";\n";
h += "\t\tstatic "+className+" *$() {\n";
h += "\t\t\tstatic "+className+" instance;\n";
h += "\t\t\treturn &instance;\n";
h += "\t\t}\n";
h += "};\n";		
fs.writeFileSync("../"+className+".h",h,"utf8");

var mm = "#import \""+className+".h\"\n"; 
mm += className+"::"+className+"() {\n"
mm += "\tstatic unsigned int _data["+(uint>>2)+"] = {\n";
mm += str.slice(0,-1)+"\n";
mm += "\t};\n";
mm += "\tthis->bytes=(unsigned char *)_data;\n";
mm += "}";
fs.writeFileSync("../"+className+".mm",mm,"utf8");