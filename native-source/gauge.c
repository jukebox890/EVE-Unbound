/* BossLab 0.3.30. Original narrow Lua C-function bridge; no UE4SS ABI imports.
 * Invoked synchronously by Lua on the game thread. No hooks or worker threads.
 * Only the three current resource stats are passed to the game's own setter.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
__declspec(dllimport) int sprintf(char *, const char *, ...);
#include "signatures.h"
static HMODULE self_module;
static DWORD owner_thread;
static LONG busy;
static WCHAR req_path[1024],res_path[1024];
static char request[256], response[1024];
static const char *failure;
static unsigned long long sequence;
static uintptr_t image_base;
static float before[3],maximum[3],after[3];
static uintptr_t selected_actor;

BOOL WINAPI DllMain(HINSTANCE h,DWORD why,LPVOID reserved) {
    (void)reserved;
    if(why==DLL_PROCESS_ATTACH) self_module=h;
    return TRUE;
}
static int readable(uintptr_t p,SIZE_T n) {
    MEMORY_BASIC_INFORMATION m;
    if(p<0x10000 || p+n<p) return 0;
    while(n) {
        if(!VirtualQuery((void*)p,&m,sizeof(m)) || m.State!=MEM_COMMIT ||
           (m.Protect&(PAGE_GUARD|PAGE_NOACCESS))) return 0;
        DWORD protect=m.Protect&0xff;
        if(protect!=PAGE_READONLY && protect!=PAGE_READWRITE && protect!=PAGE_WRITECOPY &&
           protect!=PAGE_EXECUTE_READ && protect!=PAGE_EXECUTE_READWRITE && protect!=PAGE_EXECUTE_WRITECOPY) return 0;
        SIZE_T left=(uintptr_t)m.BaseAddress+m.RegionSize-p;
        if(!left) return 0;
        if(left>=n) return 1;
        p+=left;n-=left;
    }
    return 1;
}
static int read_mem(uintptr_t p,void *out,SIZE_T n) {
    SIZE_T got=0;
    return readable(p,n) && ReadProcessMemory(GetCurrentProcess(),(void*)p,out,n,&got) && got==n;
}
static uintptr_t ptr(uintptr_t p) {
    uintptr_t v=0;if(!read_mem(p,&v,8)) failure="UNREADABLE_POINTER";return v;
}
static int number(char **cursor,unsigned long long *value,unsigned radix) {
    char *p=*cursor;unsigned count=0;unsigned long long v=0;
    while(*p==' ' || *p=='\r' || *p=='\n') ++p;
    while(*p) {
        unsigned d=(*p>='0'&&*p<='9')?*p-'0':(*p>='a'&&*p<='f')?*p-'a'+10:(*p>='A'&&*p<='F')?*p-'A'+10:99;
        if(d>=radix) break;
        if(v>(~0ULL-d)/radix) return 0;
        v=v*radix+d;++p;++count;
    }
    if(!count || (*p && *p!=' ' && *p!='\r' && *p!='\n')) return 0;
    *cursor=p;*value=v;return 1;
}
static int paths(void) {
    DWORD n=GetModuleFileNameW(self_module,req_path,1000);
    if(!n || n>=1000) return 0;
    while(n && req_path[n-1]!='\\' && req_path[n-1]!='/') --n;
    if(!n) return 0;
    for(DWORD i=0;i<n;i++) res_path[i]=req_path[i];
    const WCHAR *r=L"request.txt",*s=L"response.txt";
    DWORD i=0;do{req_path[n+i]=r[i];}while(r[i++]);
    i=0;do{res_path[n+i]=s[i];}while(s[i++]);return 1;
}
static int signature(uintptr_t rva,const unsigned char *expected,SIZE_T n) {
    if(!readable(image_base+rva,n)) return 0;
    const unsigned char *actual=(void*)(image_base+rva);
    for(SIZE_T i=0;i<n;i++) if(actual[i]!=expected[i]) return 0;
    return 1;
}
static int build_ok(void) {
    image_base=(uintptr_t)GetModuleHandleW(NULL);
    if(!readable(image_base,0x1000)) return 0;
    IMAGE_DOS_HEADER *dos=(void*)image_base;
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<0 || dos->e_lfanew>0x800) return 0;
    IMAGE_NT_HEADERS64 *nt=(void*)(image_base+dos->e_lfanew);
    if(nt->Signature!=IMAGE_NT_SIGNATURE || nt->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64 ||
       nt->FileHeader.TimeDateStamp!=0x6a6a3b74 || nt->OptionalHeader.SizeOfImage!=0x15981000) return 0;
    return signature(0x1a684f0,sig_setter,sizeof(sig_setter)) &&
           signature(0x201b1e0,sig_bridge,sizeof(sig_bridge)) &&
           signature(0x1c77620,sig_normalize,sizeof(sig_normalize)) &&
           signature(0x1cc2590,sig_selected,sizeof(sig_selected)) &&
           signature(0x1a97c40,sig_client,sizeof(sig_client)) &&
           signature(0x1a97cb0,sig_system,sizeof(sig_system));
}
static int valid_float(float f,float low,float high) {return f==f && f>=low && f<=high;}
static void fill(uintptr_t pawn,uintptr_t controller,uintptr_t world) {
    typedef void *(__fastcall *Lookup)(void*,const void*);
    typedef void (__fastcall *Setter)(void*,int,float,unsigned char);
    const int stat[3]={14,18,22};
    float stats[131];
    failure="UNSUPPORTED_EXECUTABLE";if(!build_ok()) return;
    failure="CONTEXT_MISMATCH";
    if(!pawn || !controller || !world || ptr(controller+0x2f8)!=pawn || ptr(pawn+0x300)!=controller) return;
    failure="PLAYER_UNAVAILABLE";
    uintptr_t client=ptr(image_base+0x7032570);if(!client) return;
    uintptr_t manager=ptr(client+0xc8);if(!manager) return;
    int count=0,index=-1;
    if(!read_mem(manager+0x30,&count,4) || !read_mem(manager+0x3c,&index,4) || count<1 || count>1024 || index<0 || index>=count) return;
    uintptr_t array=ptr(manager+0x28);if(!array) return;
    selected_actor=ptr(array+8*(uintptr_t)index);if(!selected_actor || !readable(selected_actor,0x4b4)) return;
    uintptr_t system=ptr(image_base+0x7032558);if(!system) return;
    uintptr_t bridge=ptr(system+0x48);if(!bridge) return;
    failure="ACTOR_IDENTITY_MISMATCH";
    Lookup lookup=(Lookup)(image_base+0x201b1e0);
    if((uintptr_t)lookup((void*)bridge,(void*)(selected_actor+0x4a4))!=pawn) return;
    failure="INVALID_STATS";
    if(!read_mem(selected_actor+0x118,stats,sizeof(stats))) return;
    if(!valid_float(stats[2],1,1e9f) || !valid_float(stats[1],0.001f,stats[2])) {failure="PLAYER_NOT_ALIVE";return;}
    for(int i=0;i<3;i++) {
        before[i]=stats[stat[i]];maximum[i]=stats[stat[i]+1];
        if(!valid_float(maximum[i],0.001f,1e6f) || !valid_float(before[i],0,maximum[i])) return;
    }
    /* All identity/range checks precede every write. Check possession once more. */
    failure="CONTEXT_MISMATCH";
    if(ptr(controller+0x2f8)!=pawn || ptr(pawn+0x300)!=controller) return;
    Setter setter=(Setter)(image_base+0x1a684f0);
    failure="SETTER_EXCEPTION";
    for(int i=0;i<3;i++) if(before[i]!=maximum[i]) setter((void*)selected_actor,stat[i],maximum[i],0);
    failure="READBACK_MISMATCH";
    for(int i=0;i<3;i++) {
        if(!read_mem(selected_actor+0x118+stat[i]*4,&after[i],4) || after[i]!=maximum[i]) return;
    }
    failure=NULL;
}
__declspec(dllexport) int BossLabRun(void *unused_lua_state) {
    (void)unused_lua_state;
    if(InterlockedCompareExchange(&busy,1,0)!=0) return 0;
    if(!paths()) {InterlockedExchange(&busy,0);return 0;}
    sequence=0;selected_actor=0;failure="BAD_REQUEST";
    __try {
        HANDLE file=CreateFileW(req_path,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
        DWORD length=0;BOOL read=FALSE;
        if(file!=INVALID_HANDLE_VALUE){read=ReadFile(file,request,sizeof(request)-1,&length,NULL);CloseHandle(file);}
        if(read && length && length<sizeof(request)-1) {
            request[length]=0;char *cursor=request;
            unsigned long long version=0,op=0,pawn=0,pc=0,world=0;
            if(number(&cursor,&version,10) && version==1 && number(&cursor,&sequence,10) && sequence &&
               number(&cursor,&op,10) && op==1 && number(&cursor,&pawn,16) && number(&cursor,&pc,16) && number(&cursor,&world,16)) {
                while(*cursor==' ' || *cursor=='\n' || *cursor=='\r') ++cursor;
                if(!*cursor) {
                    DWORD current=GetCurrentThreadId();
                    if(!owner_thread) owner_thread=current;
                    if(owner_thread!=current) failure="WRONG_THREAD";
                    else fill((uintptr_t)pawn,(uintptr_t)pc,(uintptr_t)world);
                }
            }
        }
    } __except(EXCEPTION_EXECUTE_HANDLER) {failure="NATIVE_EXCEPTION";}
    int len;
    if(failure) len=sprintf(response,"%llu ERROR %s\n",sequence,failure);
    else len=sprintf(response,"%llu OK actor=%llx beta=%.6g/%.6g->%.6g burst=%.6g/%.6g->%.6g tachy=%.6g/%.6g->%.6g\n",
        sequence,(unsigned long long)selected_actor,(double)before[0],(double)maximum[0],(double)after[0],
        (double)before[1],(double)maximum[1],(double)after[1],(double)before[2],(double)maximum[2],(double)after[2]);
    HANDLE out=CreateFileW(res_path,GENERIC_WRITE,FILE_SHARE_READ,NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
    if(out!=INVALID_HANDLE_VALUE) {DWORD written;WriteFile(out,response,(DWORD)len,&written,NULL);CloseHandle(out);}
    InterlockedExchange(&busy,0);return 0;
}
