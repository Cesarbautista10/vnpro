from intelhex import IntelHex
import sys
import os


if (len(sys.argv)<3):
    print("Need parameter for HEX file and padding size")
    exit()
hexFilePath = sys.argv[1]
paddedSize = int(sys.argv[2])
hexObj = IntelHex(hexFilePath)
print("Original Hex address ranging from %d to %d" % (hexObj.minaddr(),hexObj.maxaddr()))
if (paddedSize<=hexObj.maxaddr()):
    print("padding size not large enough")
    exit()

basename = os.path.basename(hexFilePath)

paddingStartAddr = hexObj.maxaddr()+1

for i in range(paddingStartAddr, paddedSize):
    hexObj[i] = 0x55;

hexObj.write_hex_file("padded0x55_"+str(paddedSize)+"_"+basename);

for i in range(paddingStartAddr, paddedSize):
    hexObj[i] = 0xAA;

hexObj.write_hex_file("padded0xAA_"+str(paddedSize)+"_"+basename);

print("PaddedHex address ranging from %d to %d" % (hexObj.minaddr(),hexObj.maxaddr()))
