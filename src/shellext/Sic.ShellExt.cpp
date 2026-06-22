// Sic.ShellExt - Windows 11 モダン コンテキスト メニュー用 IExplorerCommand ハンドラ
//
// .lnk を右クリックしたときにモダン メニュー（第一階層）へ「アイコンを変更」を出し、
// クリックで隣の ShortcutIconChanger.exe を選択された .lnk 付きで起動するだけの薄いランチャ。
// WRL/ATL に依存しない生 COM 実装。CRT は静的リンク (/MT) で追加ランタイム依存なし。
// スパース MSIX パッケージ (installer\sparse) の com:SurrogateServer から起動される。
//
// 日本語リテラルは codepage 事故を避けるため \u エスケープで記述する。

#include <windows.h>
#include <shobjidl_core.h>
#include <shlwapi.h>
#include <strsafe.h>
#include <new>

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "user32.lib")

// パッケージ(スパース MSIX)のサロゲートから子プロセスを起動すると、その子は既定でパッケージ ID を
// 継承し、%LOCALAPPDATA% への書き込みが Packages\<PFN>\LocalCache\... へ透過的にリダイレクトされる。
// アプリ本体(ShortcutIconChanger.exe)はその影響で、実際に書き込んだ cache\*.ico の物理パスと、
// .lnk に記録する IconLocation 文字列(非リダイレクトの %LOCALAPPDATA% 形)が食い違い、
// Explorer がアイコン ファイルを見つけられずショートカットが白く表示される。これを避けるため、
// アプリは「通常の デスクトップ アプリ」(パッケージ ID 無し)として起動する。
// 下記は Windows 10 1703+ の DESKTOP_APP_POLICY 属性。古い SDK でも使えるよう未定義なら自前定義する。
#ifndef PROC_THREAD_ATTRIBUTE_DESKTOP_APP_POLICY
#define PROC_THREAD_ATTRIBUTE_DESKTOP_APP_POLICY \
    ProcThreadAttributeValue(12, FALSE, TRUE, FALSE)  // ProcThreadAttributeDesktopAppPolicy
#endif
#ifndef PROCESS_CREATION_DESKTOP_APP_BREAKAWAY_ENABLE_PROCESS_TREE
#define PROCESS_CREATION_DESKTOP_APP_BREAKAWAY_ENABLE_PROCESS_TREE 0x00000001
#endif

// {B6E6D7EA-EEBA-4B94-84CE-E34DCF06AD5C}
static const GUID CLSID_ChangeIconCommand =
    { 0xB6E6D7EA, 0xEEBA, 0x4B94, { 0x84, 0xCE, 0xE3, 0x4D, 0xCF, 0x06, 0xAD, 0x5C } };

static HMODULE g_hModule = nullptr;
static LONG    g_cRef     = 0;   // サーバ全体の生存オブジェクト/ロック数

// このDLLと同じフォルダにある ShortcutIconChanger.exe のフルパスを得る。
static bool GetAppExePath(wchar_t* out, size_t cch)
{
    wchar_t dll[MAX_PATH];
    DWORD n = GetModuleFileNameW(g_hModule, dll, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return false;
    wchar_t* slash = wcsrchr(dll, L'\\');
    if (!slash) return false;
    *(slash + 1) = L'\0';
    if (FAILED(StringCchCopyW(out, cch, dll))) return false;
    if (FAILED(StringCchCatW(out, cch, L"ShortcutIconChanger.exe"))) return false;
    return true;
}

// アプリ本体を起動する。
// [GitHub/MSI スパース ビルド: 既定] サロゲート(dllhost)から起動した子は既定でパッケージ ID を継承し、
// %LOCALAPPDATA% への書き込みが Packages\<PFN>\LocalCache\... へリダイレクトされてアイコン パスが
// 食い違う(白アイコン)。対象 exe はパッケージの登録済み Application のため DESKTOP_APP_BREAKAWAY
// 単体では ID を剥がせない。そこで「パッケージ ID を持たない explorer.exe(シェル)を親プロセスに指定」
// して起動し、ID の継承元を断つ(非リダイレクトの実 %LOCALAPPDATA% へ書き込み、.lnk と一致)。
// [Store(完全 MSIX)ビルド: SIC_STORE 定義時] コンテナ ID を尊重し reparent しない(審査上も自然)。
// 書き込みは LocalCache へリダイレクトされるが、アプリ側が実体パス(GetFinalPathNameByHandle)を
// 解決して .lnk に記録するため、アイコンは正しく表示される。
#ifndef SIC_STORE
static HANDLE OpenShellProcessForReparent()
{
    HWND shell = GetShellWindow();
    if (!shell) return nullptr;
    DWORD pid = 0;
    GetWindowThreadProcessId(shell, &pid);
    if (pid == 0) return nullptr;
    return OpenProcess(PROCESS_CREATE_PROCESS, FALSE, pid);
}
#endif

static void LaunchAppUnpackaged(const wchar_t* exe, const wchar_t* lnkPath)
{
    // 作業ディレクトリ = exe のあるフォルダ
    wchar_t dir[MAX_PATH];
    if (FAILED(StringCchCopyW(dir, ARRAYSIZE(dir), exe))) { dir[0] = L'\0'; }
    else { wchar_t* slash = wcsrchr(dir, L'\\'); if (slash) *slash = L'\0'; }
    const wchar_t* workDir = (dir[0] != L'\0') ? dir : nullptr;

    // ShellExecute 用の引数 ("lnk")。
    wchar_t args[MAX_PATH + 4];
    bool haveArgs = SUCCEEDED(StringCchPrintfW(args, ARRAYSIZE(args), L"\"%s\"", lnkPath));

    bool launched = false;

#ifndef SIC_STORE
    // reparent-to-explorer + breakaway でパッケージ ID を剥がして起動(GitHub/MSI スパース版のみ)。
    // CreateProcessW は lpCommandLine を書き換える可能性があるため可変バッファ cmd に置く。
    {
        wchar_t cmd[2 * MAX_PATH + 8];
        bool haveCmd = SUCCEEDED(StringCchPrintfW(cmd, ARRAYSIZE(cmd), L"\"%s\" \"%s\"", exe, lnkPath));
        HANDLE hParent = OpenShellProcessForReparent();   // explorer.exe(パッケージ ID 無し)。失敗時 nullptr
        if (haveCmd)
        {
            DWORD attrCount = (hParent ? 1u : 0u) + 1u;   // 親プロセス(任意) + DESKTOP_APP_POLICY
            SIZE_T attrSize = 0;
            InitializeProcThreadAttributeList(nullptr, attrCount, 0, &attrSize);
            auto* attrList = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(
                HeapAlloc(GetProcessHeap(), 0, attrSize));
            if (attrList && InitializeProcThreadAttributeList(attrList, attrCount, 0, &attrSize))
            {
                bool parentSet = false;
                if (hParent)
                    parentSet = UpdateProcThreadAttribute(attrList, 0, PROC_THREAD_ATTRIBUTE_PARENT_PROCESS,
                                                          &hParent, sizeof(hParent), nullptr, nullptr) != FALSE;
                DWORD policy = PROCESS_CREATION_DESKTOP_APP_BREAKAWAY_ENABLE_PROCESS_TREE;
                bool policySet = UpdateProcThreadAttribute(attrList, 0, PROC_THREAD_ATTRIBUTE_DESKTOP_APP_POLICY,
                                                           &policy, sizeof(policy), nullptr, nullptr) != FALSE;
                if (parentSet || policySet)
                {
                    STARTUPINFOEXW si = {};
                    si.StartupInfo.cb = sizeof(si);
                    si.lpAttributeList = attrList;
                    PROCESS_INFORMATION pi = {};
                    if (CreateProcessW(exe, cmd, nullptr, nullptr, FALSE,
                                       EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                                       nullptr, workDir, &si.StartupInfo, &pi))
                    {
                        CloseHandle(pi.hThread);
                        CloseHandle(pi.hProcess);
                        launched = true;
                    }
                }
                DeleteProcThreadAttributeList(attrList);
            }
            if (attrList) HeapFree(GetProcessHeap(), 0, attrList);
        }
        if (hParent) CloseHandle(hParent);
    }
#endif

    // 通常起動 / フォールバック。Store ビルド(SIC_STORE)は常にこちら。リダイレクトが起きうるが、
    // アプリ側でも実体パスを解決して .lnk へ記録するため白アイコンは回避される。
    if (!launched)
        ShellExecuteW(nullptr, L"open", exe, haveArgs ? args : nullptr, workDir, SW_SHOWNORMAL);
}

static bool IsJapaneseUi()
{
    return PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_JAPANESE;
}

// 選択が「単一の .lnk」かどうか。モダン メニューは Type="*" で登録し、ここで
// .lnk 以外を ECS_HIDDEN にすることでショートカットのときだけ項目を出す。
static bool IsSingleLnk(IShellItemArray* items)
{
    if (!items) return false;
    DWORD count = 0;
    if (FAILED(items->GetCount(&count)) || count != 1) return false;

    IShellItem* item = nullptr;
    if (FAILED(items->GetItemAt(0, &item)) || !item) return false;

    bool ok = false;
    PWSTR path = nullptr;
    if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path)
    {
        PCWSTR ext = PathFindExtensionW(path);
        ok = (ext && _wcsicmp(ext, L".lnk") == 0);
        CoTaskMemFree(path);
    }
    item->Release();
    return ok;
}

class ChangeIconCommand : public IExplorerCommand
{
public:
    ChangeIconCommand() : _ref(1) { InterlockedIncrement(&g_cRef); }

    // IUnknown
    IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv)
    {
        static const QITAB qit[] =
        {
            QITABENT(ChangeIconCommand, IExplorerCommand),
            { nullptr, 0 },
        };
        return QISearch(this, qit, riid, ppv);
    }
    IFACEMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&_ref); }
    IFACEMETHODIMP_(ULONG) Release()
    {
        ULONG r = InterlockedDecrement(&_ref);
        if (r == 0) delete this;
        return r;
    }

    // IExplorerCommand
    IFACEMETHODIMP GetTitle(IShellItemArray*, LPWSTR* ppszName)
    {
        // 「アイコンを変更」 / "Change icon"
        return SHStrDupW(IsJapaneseUi() ? L"\u30A2\u30A4\u30B3\u30F3\u3092\u5909\u66F4"
                                        : L"Change icon", ppszName);
    }
    IFACEMETHODIMP GetIcon(IShellItemArray*, LPWSTR* ppszIcon)
    {
        wchar_t exe[MAX_PATH];
        if (!GetAppExePath(exe, ARRAYSIZE(exe))) { *ppszIcon = nullptr; return E_FAIL; }
        wchar_t icon[MAX_PATH + 8];
        if (FAILED(StringCchPrintfW(icon, ARRAYSIZE(icon), L"%s,0", exe))) { *ppszIcon = nullptr; return E_FAIL; }
        return SHStrDupW(icon, ppszIcon);
    }
    IFACEMETHODIMP GetToolTip(IShellItemArray*, LPWSTR* ppszInfotip) { *ppszInfotip = nullptr; return E_NOTIMPL; }
    IFACEMETHODIMP GetCanonicalName(GUID* pguid) { *pguid = GUID_NULL; return S_OK; }
    IFACEMETHODIMP GetState(IShellItemArray* psiItemArray, BOOL, EXPCMDSTATE* pCmdState)
    {
        // .lnk 単一選択のときだけ表示する。
        *pCmdState = IsSingleLnk(psiItemArray) ? ECS_ENABLED : ECS_HIDDEN;
        return S_OK;
    }
    IFACEMETHODIMP GetFlags(EXPCMDFLAGS* pFlags) { *pFlags = ECF_DEFAULT; return S_OK; }
    IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** ppEnum) { *ppEnum = nullptr; return E_NOTIMPL; }

    IFACEMETHODIMP Invoke(IShellItemArray* psiItemArray, IBindCtx*)
    {
        if (!psiItemArray) return E_INVALIDARG;
        DWORD count = 0;
        if (FAILED(psiItemArray->GetCount(&count)) || count == 0) return S_OK;

        IShellItem* item = nullptr;
        HRESULT hr = psiItemArray->GetItemAt(0, &item);
        if (FAILED(hr)) return hr;

        PWSTR path = nullptr;
        hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
        if (SUCCEEDED(hr) && path)
        {
            wchar_t exe[MAX_PATH];
            if (GetAppExePath(exe, ARRAYSIZE(exe)))
                LaunchAppUnpackaged(exe, path);
            CoTaskMemFree(path);
        }
        item->Release();
        return S_OK;
    }

private:
    ~ChangeIconCommand() { InterlockedDecrement(&g_cRef); }
    LONG _ref;
};

class ClassFactory : public IClassFactory
{
public:
    ClassFactory() : _ref(1) { InterlockedIncrement(&g_cRef); }

    IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv)
    {
        static const QITAB qit[] =
        {
            QITABENT(ClassFactory, IClassFactory),
            { nullptr, 0 },
        };
        return QISearch(this, qit, riid, ppv);
    }
    IFACEMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&_ref); }
    IFACEMETHODIMP_(ULONG) Release()
    {
        ULONG r = InterlockedDecrement(&_ref);
        if (r == 0) delete this;
        return r;
    }

    IFACEMETHODIMP CreateInstance(IUnknown* pOuter, REFIID riid, void** ppv)
    {
        *ppv = nullptr;
        if (pOuter) return CLASS_E_NOAGGREGATION;
        ChangeIconCommand* p = new (std::nothrow) ChangeIconCommand();
        if (!p) return E_OUTOFMEMORY;
        HRESULT hr = p->QueryInterface(riid, ppv);
        p->Release();
        return hr;
    }
    IFACEMETHODIMP LockServer(BOOL fLock)
    {
        if (fLock) InterlockedIncrement(&g_cRef); else InterlockedDecrement(&g_cRef);
        return S_OK;
    }

private:
    ~ClassFactory() { InterlockedDecrement(&g_cRef); }
    LONG _ref;
};

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv)
{
    if (!IsEqualCLSID(rclsid, CLSID_ChangeIconCommand)) return CLASS_E_CLASSNOTAVAILABLE;
    ClassFactory* f = new (std::nothrow) ClassFactory();
    if (!f) return E_OUTOFMEMORY;
    HRESULT hr = f->QueryInterface(riid, ppv);
    f->Release();
    return hr;
}

STDAPI DllCanUnloadNow()
{
    return (g_cRef == 0) ? S_OK : S_FALSE;
}

BOOL WINAPI DllMain(HINSTANCE hInst, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        g_hModule = hInst;
        DisableThreadLibraryCalls(hInst);
    }
    return TRUE;
}
