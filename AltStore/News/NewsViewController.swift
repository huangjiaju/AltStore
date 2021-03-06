//
//  NewsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import SafariServices

import Roxas

import Nuke

private class AppBannerFooterView: UICollectionReusableView
{
    let bannerView = AppBannerView(frame: .zero)
    let tapGestureRecognizer = UITapGestureRecognizer(target: nil, action: nil)
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.addSubview(self.bannerView, pinningEdgesWith: UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20))
        self.addGestureRecognizer(self.tapGestureRecognizer)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class NewsViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    private lazy var placeholderView = RSTPlaceholderView(frame: .zero)
    
    private var prototypeCell: NewsCollectionViewCell!
    
    private var loadingState: LoadingState = .loading {
        didSet {
            self.update()
        }
    }
    
    // Cache
    private var cachedCellSizes = [String: CGSize]()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.prototypeCell = NewsCollectionViewCell.instantiate(with: NewsCollectionViewCell.nib!)
        self.prototypeCell.translatesAutoresizingMaskIntoConstraints = false
        self.prototypeCell.contentView.translatesAutoresizingMaskIntoConstraints = false
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.collectionView.register(NewsCollectionViewCell.nib, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        self.collectionView.register(AppBannerFooterView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "AppBanner")
        
        self.registerForPreviewing(with: self, sourceView: self.collectionView)
        
        self.update()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.fetchSource()
    }
    
    override func viewWillLayoutSubviews()
    {
        super.viewWillLayoutSubviews()
        
        if self.collectionView.contentInset.bottom != 20
        {
            // Triggers collection view update in iOS 13, which crashes if we do it in viewDidLoad()
            // since the database might not be loaded yet.
            self.collectionView.contentInset.bottom = 20
        }
    }
}

private extension NewsViewController
{
    func makeDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<NewsItem, UIImage>
    {
        let fetchRequest = NewsItem.fetchRequest() as NSFetchRequest<NewsItem>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \NewsItem.sortIndex, ascending: false)]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: #keyPath(NewsItem.date), cacheName: nil)
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<NewsItem, UIImage>(fetchedResultsController: fetchedResultsController)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { (cell, newsItem, indexPath) in
            let cell = cell as! NewsCollectionViewCell
            cell.titleLabel.text = newsItem.title
            cell.captionLabel.text = newsItem.caption
            cell.contentView.backgroundColor = newsItem.tintColor
            
            cell.imageView.image = nil
            
            if newsItem.imageURL != nil
            {
                cell.imageView.isIndicatingActivity = true
                cell.imageView.isHidden = false
            }
            else
            {
                cell.imageView.isIndicatingActivity = false
                cell.imageView.isHidden = true
            }
        }
        dataSource.prefetchHandler = { (newsItem, indexPath, completionHandler) in
            guard let imageURL = newsItem.imageURL else { return nil }
            
            return RSTAsyncBlockOperation() { (operation) in
                ImagePipeline.shared.loadImage(with: imageURL, progress: nil, completion: { (response, error) in
                    guard !operation.isCancelled else { return operation.finish() }
                    
                    if let image = response?.image
                    {
                        completionHandler(image, nil)
                    }
                    else
                    {
                        completionHandler(nil, error)
                    }
                })
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! NewsCollectionViewCell
            cell.imageView.isIndicatingActivity = false
            cell.imageView.image = image
            
            if let error = error
            {
                print("Error loading image:", error)
            }
        }
        
        dataSource.placeholderView = self.placeholderView
        
        return dataSource
    }

    func fetchSource()
    {
        self.loadingState = .loading
        
        AppManager.shared.fetchSource() { (result) in
            do
            {
                let source = try result.get()
                try source.managedObjectContext?.save()
                
                DispatchQueue.main.async {
                    self.loadingState = .finished(.success(()))
                }
            }
            catch
            {
                DispatchQueue.main.async {
                    if self.dataSource.itemCount > 0
                    {
                        let toastView = ToastView(text: error.localizedDescription, detailText: nil)
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                    }
                    
                    self.loadingState = .finished(.failure(error))
                }
            }
        }
    }
    
    func update()
    {
        switch self.loadingState
        {
        case .loading:
            self.placeholderView.textLabel.isHidden = true
            self.placeholderView.detailTextLabel.isHidden = false
            
            self.placeholderView.detailTextLabel.text = NSLocalizedString("Loading...", comment: "")
            
            self.placeholderView.activityIndicatorView.startAnimating()
            
        case .finished(.failure(let error)):
            self.placeholderView.textLabel.isHidden = false
            self.placeholderView.detailTextLabel.isHidden = false
            
            self.placeholderView.textLabel.text = NSLocalizedString("Unable to Fetch News", comment: "")
            self.placeholderView.detailTextLabel.text = error.localizedDescription
            
            self.placeholderView.activityIndicatorView.stopAnimating()
            
        case .finished(.success):
            self.placeholderView.textLabel.isHidden = true
            self.placeholderView.detailTextLabel.isHidden = true
            
            self.placeholderView.activityIndicatorView.stopAnimating()
        }
    }
}

private extension NewsViewController
{
    @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer)
    {
        guard let footerView = gestureRecognizer.view as? UICollectionReusableView else { return }
        
        let indexPaths = self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)
        
        guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
            let supplementaryView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath)
            return supplementaryView == footerView
        }) else { return }
        
        let item = self.dataSource.item(at: indexPath)
        guard let storeApp = item.storeApp else { return }
        
        let appViewController = AppViewController.makeAppViewController(app: storeApp)
        self.navigationController?.pushViewController(appViewController, animated: true)
    }
    
    @objc func performAppAction(_ sender: PillButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        let indexPaths = self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)
        
        guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
            let supplementaryView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath)
            return supplementaryView?.frame.contains(point) ?? false
        }) else { return }
        
        let app = self.dataSource.item(at: indexPath)
        guard let storeApp = app.storeApp else { return }
        
        if let installedApp = app.storeApp?.installedApp
        {
            self.open(installedApp)
        }
        else
        {
            self.install(storeApp, at: indexPath)
        }
    }
    
    @objc func install(_ storeApp: StoreApp, at indexPath: IndexPath)
    {
        let previousProgress = AppManager.shared.installationProgress(for: storeApp)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        _ = AppManager.shared.install(storeApp, presentingViewController: self) { (result) in
            DispatchQueue.main.async {
                switch result
                {
                case .failure(OperationError.cancelled): break // Ignore
                case .failure(let error):
                    let toastView = ToastView(text: error.localizedDescription, detailText: nil)
                    toastView.show(in: self.navigationController?.view ?? self.view, duration: 2)
                    
                case .success: print("Installed app:", storeApp.bundleIdentifier)
                }
                
                UIView.performWithoutAnimation {
                    self.collectionView.reloadSections(IndexSet(integer: indexPath.section))
                }
            }
        }
        
        UIView.performWithoutAnimation {
            self.collectionView.reloadSections(IndexSet(integer: indexPath.section))
        }
    }
    
    func open(_ installedApp: InstalledApp)
    {
        UIApplication.shared.open(installedApp.openAppURL)
    }
}

extension NewsViewController
{
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        let newsItem = self.dataSource.item(at: indexPath)
        
        if let externalURL = newsItem.externalURL
        {
            let safariViewController = SFSafariViewController(url: externalURL)
            safariViewController.preferredControlTintColor = newsItem.tintColor
            self.present(safariViewController, animated: true, completion: nil)
        }
        else if let storeApp = newsItem.storeApp
        {
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            self.navigationController?.pushViewController(appViewController, animated: true)
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let item = self.dataSource.item(at: indexPath)
        
        let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "AppBanner", for: indexPath) as! AppBannerFooterView
        guard let storeApp = item.storeApp else { return footerView }
        
        footerView.bannerView.titleLabel.text = storeApp.name
        footerView.bannerView.subtitleLabel.text = storeApp.developerName
        footerView.bannerView.tintColor = storeApp.tintColor
        footerView.bannerView.betaBadgeView.isHidden = !storeApp.isBeta
        footerView.bannerView.button.addTarget(self, action: #selector(NewsViewController.performAppAction(_:)), for: .primaryActionTriggered)
        footerView.tapGestureRecognizer.addTarget(self, action: #selector(NewsViewController.handleTapGesture(_:)))
        
        footerView.bannerView.button.isIndicatingActivity = false
        
        if storeApp.installedApp == nil
        {
            footerView.bannerView.button.setTitle(NSLocalizedString("FREE", comment: ""), for: .normal)
            
            let progress = AppManager.shared.installationProgress(for: storeApp)
            footerView.bannerView.button.progress = progress
            footerView.bannerView.button.isInverted = false
            
            if Date() < storeApp.versionDate
            {
                footerView.bannerView.button.countdownDate = storeApp.versionDate
            }
            else
            {
                footerView.bannerView.button.countdownDate = nil
            }
        }
        else
        {
            footerView.bannerView.button.setTitle(NSLocalizedString("OPEN", comment: ""), for: .normal)
            footerView.bannerView.button.progress = nil
            footerView.bannerView.button.isInverted = true
            footerView.bannerView.button.countdownDate = nil
        }
        
        Nuke.loadImage(with: storeApp.iconURL, into: footerView.bannerView.iconImageView)
        
        return footerView
    }
}

extension NewsViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        let padding = 40 as CGFloat
        let width = collectionView.bounds.width - padding
        
        let item = self.dataSource.item(at: indexPath)
        
        if let previousSize = self.cachedCellSizes[item.identifier]
        {
            return previousSize
        }
        
        let widthConstraint = self.prototypeCell.contentView.widthAnchor.constraint(equalToConstant: width)
        NSLayoutConstraint.activate([widthConstraint])
        defer { NSLayoutConstraint.deactivate([widthConstraint]) }
        
        self.dataSource.cellConfigurationHandler(self.prototypeCell, item, indexPath)
        
        let size = self.prototypeCell.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.cachedCellSizes[item.identifier] = size
        return size
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize
    {
        let item = self.dataSource.item(at: IndexPath(row: 0, section: section))
        
        if item.storeApp != nil
        {
            return CGSize(width: 88, height: 88)
        }
        else
        {
            return .zero
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets
    {
        var insets = UIEdgeInsets(top: 30, left: 20, bottom: 13, right: 20)
        
        if section == 0
        {
            insets.top = 10
        }
        
        return insets
    }
}

extension NewsViewController: UIViewControllerPreviewingDelegate
{
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController?
    {
        if let indexPath = self.collectionView.indexPathForItem(at: location), let cell = self.collectionView.cellForItem(at: indexPath)
        {
            // Previewing news item.
            
            previewingContext.sourceRect = cell.frame
            
            let newsItem = self.dataSource.item(at: indexPath)
            
            if let externalURL = newsItem.externalURL
            {
                let safariViewController = SFSafariViewController(url: externalURL)
                safariViewController.preferredControlTintColor = newsItem.tintColor
                return safariViewController
            }
            else if let storeApp = newsItem.storeApp
            {
                let appViewController = AppViewController.makeAppViewController(app: storeApp)
                return appViewController
            }
            
            return nil
        }
        else
        {
            // Previewing app banner (or nothing).
            
            let indexPaths = self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)
            
            guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
                let layoutAttributes = self.collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionFooter, at: indexPath)
                return layoutAttributes?.frame.contains(location) ?? false
            }) else { return nil }
            
            guard let layoutAttributes = self.collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionFooter, at: indexPath) else { return nil }
            previewingContext.sourceRect = layoutAttributes.frame
            
            let item = self.dataSource.item(at: indexPath)
            guard let storeApp = item.storeApp else { return nil }
            
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            return appViewController
        }
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController)
    {
        if let safariViewController = viewControllerToCommit as? SFSafariViewController
        {
            self.present(safariViewController, animated: true, completion: nil)
        }
        else
        {
            self.navigationController?.pushViewController(viewControllerToCommit, animated: true)
        }
    }
}
