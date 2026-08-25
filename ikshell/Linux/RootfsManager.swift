import Foundation

/// 管理 Alpine rootfs 的下载与导入 (fakefs 格式)
///
/// 流程:
///   1. 下载 Alpine aarch64 minirootfs tar.gz 到临时目录
///   2. 调用引擎的 fakefs_import() 将 tar.gz 转为 fakefs SQLite 数据库
///   3. 存储到 Documents/rootfs/ (引擎 boot 时在其下找 data/ 子目录)
class RootfsManager {
    /// Alpine aarch64 minirootfs URL (guest arch = aarch64, matches the
    /// Asbestos ARM64 engine from ios-linuxkit).
    /// Updated to v3.20 for broader package compatibility with main ikshell target.
    static let alpineURL = "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/aarch64/alpine-minirootfs-3.20.3-aarch64.tar.gz"

    /// rootfs 在 App 沙箱中的存储路径
    var rootfsPath: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("rootfs").path
    }

    /// 检查 rootfs 是否已就绪 (data/ 子目录存在)
    var isRootfsReady: Bool {
        let dataDir = rootfsPath + "/data"
        return FileManager.default.fileExists(atPath: dataDir)
    }

    // MARK: - 公开方法

    /// 准备 rootfs: 如果已存在直接返回; 否则下载 + 导入
    func prepareRootfs(completion: @escaping (Result<String, Error>) -> Void) {
        if isRootfsReady {
            completion(.success(rootfsPath))
            return
        }
        downloadAndImport(completion: completion)
    }

    // MARK: - 下载 + 导入

    private func downloadAndImport(completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: Self.alpineURL)!
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let tempURL = tempURL else {
                completion(.failure(NSError(domain: "RootfsManager", code: -1,
                                           userInfo: [NSLocalizedDescriptionKey: "下载失败"])))
                return
            }

            // 把临时文件移到可控位置 (tempURL 在系统临时目录, 可能被自动清理)
            let fm = FileManager.default
            let archivePath = NSTemporaryDirectory() + "alpine-minirootfs.tar.gz"
            try? fm.removeItem(atPath: archivePath)
            do {
                try fm.moveItem(at: tempURL, to: URL(fileURLWithPath: archivePath))
            } catch {
                completion(.failure(error))
                return
            }

            // 调用引擎的 fakefs_import 进行导入
            // 目标路径: rootfsPath (引擎会在其下创建 data/ 子目录)
            let dest = self.rootfsPath
            try? fm.removeItem(atPath: dest)
            try? fm.createDirectory(atPath: dest, withIntermediateDirectories: true)

            let ret = archivePath.withCString { cArchive in
                dest.withCString { cDest in
                    kernel_import_rootfs(cArchive, cDest)
                }
            }

            // 清理临时 tar.gz
            try? fm.removeItem(atPath: archivePath)

            if ret == 0 {
                // 注入 overlay 文件 (ikpkg, motd, profile.d)
                self.injectOverlay(into: dest)
                completion(.success(dest))
            } else {
                completion(.failure(NSError(domain: "RootfsManager", code: -2,
                                           userInfo: [NSLocalizedDescriptionKey: "fakefs 导入失败 (code: \(ret))"])))
            }
        }
        task.resume()
    }

    // MARK: - Overlay 注入

    /// 将 overlay 文件 (ikpkg, motd, profile.d) 注入到已导入的 fakefs rootfs 中
    ///
    /// 注意: fakefs 是 SQLite 后端的虚拟文件系统, 不能直接用 FileManager 写文件。
    /// 这里通过 App Bundle 携带 overlay 资源, 在首次启动时由引擎内的 shell 脚本
    /// 复制到正确位置 (profile.d 在 /etc/profile.d/, ikpkg 在 /usr/local/bin/)。
    /// 简化方案: 把 overlay 打包为额外 tar, 在 fakefs_import 后追加导入。
    private func injectOverlay(into rootfsPath: String) {
        // TODO: 实现 overlay 注入
        // 方案 A: 把 overlay/ 目录打包为 tar.gz, 调用 fakefs_import 追加到同一 fakefs
        // 方案 B: 在 rootfs 中放一个 /etc/profile.d/ikshell-bootstrap.sh,
        //         首次启动时从 App Bundle 复制 overlay 文件
        // 当前: 暂不注入 (motd/profile.d 缺失不影响核心功能, ikpkg 可手动安装)
    }
}
