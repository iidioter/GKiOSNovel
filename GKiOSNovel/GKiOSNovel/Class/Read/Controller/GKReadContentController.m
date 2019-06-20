//
//  GKReadContentController.m
//  GKiOSNovel
//
//  Created by wangws1990 on 2019/6/19.
//  Copyright © 2019 wangws1990. All rights reserved.
//

#import "GKReadContentController.h"
#import "GKReadViewController.h"
#import "GKBookSourceModel.h"
#import "GKBookChapterModel.h"
#import "GKBookContentModel.h"
#import "GKBookReadModel.h"
#import "GKReadTopView.h"
#import "GKReadBottomView.h"
#import "GKReadView.h"
@interface GKReadContentController ()<UIPageViewControllerDelegate,UIPageViewControllerDataSource>

@property (strong, nonatomic) UIPageViewController *pageViewController;

@property (strong, nonatomic) GKReadTopView *topView;
@property (strong, nonatomic) GKReadBottomView *bottomView;

@property (strong, nonatomic) GKBookDetailModel *model;
@property (strong, nonatomic) GKBookSourceInfo *bookSource;
@property (strong, nonatomic) GKBookChapterInfo *bookChapter;
@property (strong, nonatomic) GKBookContentModel *bookContent;

@property (strong, nonatomic) GKBookReadModel *bookModel;

@property (assign, nonatomic) NSInteger chapter;
@property (assign, nonatomic) NSInteger pageIndex;
@end

@implementation GKReadContentController
+ (instancetype)vcWithBookDetailModel:(GKBookDetailModel *)model{
    GKReadContentController *vc = [[[self class] alloc] init];
    vc.model = model;
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadUI];
    [GKBookReadDataQueue getDataFromDataBase:self.model._id completion:^(GKBookReadModel * _Nonnull bookModel) {
        if (bookModel.bookSource.bookSourceId && bookModel.bookChapter.link) {
            self.bookModel = bookModel;
            self.chapter = bookModel.bookChapter.chapterIndex ?: 0;
            self.pageIndex = bookModel.bookContent.pageIndex ?: 0;
            [self loadBookContent:YES chapter:self.chapter];
        }else{
            self.chapter = 0;
            self.pageIndex = 0;
            [self loadData];
        }
    }];
}
- (void)loadUI{
    self.topView.titleLab.text = self.model.title?:@"";
    self.fd_prefersNavigationBarHidden = YES;
    self.pageViewController = [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal options:nil];
    self.pageViewController.doubleSided = YES;
    
    
    self.pageViewController.dataSource = self;
    self.pageViewController.delegate = self;
    [self addChildViewController:self.pageViewController];
    [self.view addSubview:self.pageViewController.view];
    
    [self.pageViewController.view mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.pageViewController.view.superview);
    }];
    
    [self.pageViewController didMoveToParentViewController:self];

    [self performSelector:@selector(tapAction) withObject:nil afterDelay:2];
    [self.view addSubview:self.topView];
    [self.topView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.top.equalTo(self.topView.superview);
        make.height.offset(NAVI_BAR_HIGHT);
    }];
    [self.view addSubview:self.bottomView];
    [self.bottomView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(self.bottomView.superview);
        make.height.offset(TAB_BAR_ADDING + 49);
    }];
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.view addSubview:btn];
    [btn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.height.offset(100);
        make.center.equalTo(btn.superview);
    }];
    [btn addTarget:self action:@selector(tapAction) forControlEvents:UIControlEventTouchUpInside];
}
- (UIViewController *)viewControllerAtPage:(NSUInteger)pageIndex chapter:(NSInteger)chapterIndex
{
    GKReadViewController *vc = [[GKReadViewController alloc] init];
    self.pageIndex = pageIndex;
    if (self.chapter != chapterIndex) {
        self.chapter = chapterIndex;
        [self loadBookContent:NO chapter:self.chapter];
    }
    [vc setCurrentPage:pageIndex totalPage:self.bookContent.pageCount chapter:self.chapter title:self.bookContent.title content:[self.bookContent getContentAtt:pageIndex]];
    return vc;
}
- (void)loadData{
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    dispatch_semaphore_t sem1 = dispatch_semaphore_create(0);
    dispatch_semaphore_t sem2 = dispatch_semaphore_create(0);
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        [GKNovelNetManager bookSummary:self.model._id success:^(id  _Nonnull object) {
            self.bookSource.listData = [NSArray modelArrayWithClass:GKBookSourceModel.class json:object];
            dispatch_semaphore_signal(sem1);
        } failure:^(NSString * _Nonnull error) {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        }];
    });
    dispatch_async(queue, ^{
        dispatch_semaphore_wait(sem1,DISPATCH_TIME_FOREVER);
        [GKNovelNetManager bookChapters:self.bookSource.bookSourceId success:^(id  _Nonnull object) {
            self.bookChapter = [GKBookChapterInfo modelWithJSON:object];
            dispatch_semaphore_signal(sem2);
        } failure:^(NSString * _Nonnull error) {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        }];
    });
    dispatch_async(queue, ^{
        dispatch_semaphore_wait(sem2,DISPATCH_TIME_FOREVER);
        [self loadBookContent:NO chapter:self.chapter];
    });
}

- (void)loadBookContent:(BOOL)history chapter:(NSInteger)chapterIndex{
    GKBookChapterModel *model = nil;
    if (history) {
        model = self.bookModel.bookChapter;
    }else if (!self.bookChapter){
        [self loadData];
        return;
    }
    else if(self.bookChapter.chapters.count > chapterIndex)
    {
        model = self.bookChapter.chapters[chapterIndex];
    }
    else if (self.bookChapter.chapters.count <= chapterIndex){
        [MBProgressHUD showMessage:@"没有下一章了"];
        return;
    }
    model.chapterIndex = chapterIndex;
    BOOL maxIndex = (self.pageIndex+1 == self.bookContent.pageCount) ? YES : NO;
    [GKNovelNetManager bookContent:model.link success:^(id  _Nonnull object) {
        self.bookContent = [GKBookContentModel modelWithJSON:object[@"chapter"]];
        [self.bookContent setContentPage];
        [self reloadUI:history maxIndex:maxIndex];
        [MBProgressHUD hideHUDForView:self.view animated:YES];
    } failure:^(NSString * _Nonnull error) {
        [MBProgressHUD hideHUDForView:self.view animated:YES];
    }];
}
- (void)reloadUI:(BOOL)history maxIndex:(BOOL)maxIndex
{
    if (!history) {
        self.pageIndex = maxIndex ? self.bookContent.pageCount - 1 : 0;
    }
    [self insertDataQueue];
    UIViewController *vc = [self viewControllerAtPage:self.pageIndex chapter:self.chapter];
    [self.pageViewController setViewControllers:@[vc]
                                      direction:UIPageViewControllerNavigationDirectionReverse
                                       animated:NO
                                     completion:nil];

}
- (void)insertDataQueue{
    GKBookChapterModel *chapterModel = [self.bookChapter.chapters objectSafeAtIndex:self.chapter] ? : self.bookModel.bookChapter;
    GKBookSourceInfo *souceInfo = self.bookSource ?: self.bookModel.bookSource;
    GKBookContentModel *contentModel = self.bookContent ?: self.bookModel.bookContent;
    chapterModel.chapterIndex = self.chapter;
    contentModel.pageIndex = self.pageIndex;
    
    GKBookReadModel *readModel = [GKBookReadModel vcWithBookId:self.model._id bookSource:souceInfo bookChapter:chapterModel bookContent:contentModel bookModel:self.model];
    [GKBookReadDataQueue insertDataToDataBase:readModel completion:^(BOOL success) {
        if (success) {
            NSLog(@"insert successful");
        }
    }];
}
#pragma mark UIPageViewControllerDelegate,UIPageViewControllerDataSource
- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(GKReadViewController *)viewController {
    NSInteger pageIndex = viewController.pageIndex;
    NSUInteger chapter = viewController.chapterIndex;
    if (pageIndex == 0 && chapter == 0){
        return nil;
    }
    if (pageIndex >= 0) {
        pageIndex = pageIndex - 1;
    }else{
        chapter = chapter - 1;
        pageIndex = self.bookContent.pageCount - 1;
    }
    return [self viewControllerAtPage:pageIndex chapter:chapter];
    
    
}
#pragma mark 返回下一个ViewController对象
- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(GKReadViewController *)viewController {
    NSUInteger pageIndex = viewController.pageIndex;
    NSUInteger chapter = viewController.chapterIndex;
    if (pageIndex >= self.bookContent.pageCount) {
        pageIndex = 0;
        chapter = chapter + 1;
    }else{
        pageIndex = pageIndex + 1;
    }
    return [self viewControllerAtPage:pageIndex chapter:chapter];
}
//- (void)pageViewController:(UIPageViewController *)pageViewController willTransitionToViewControllers:(NSArray<UIViewController *> *)pendingViewControllers {
//    pageViewController.view.userInteractionEnabled = NO;
//}
//- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray<UIViewController *> *)previousViewControllers transitionCompleted:(BOOL)completed{
//    if (finished) {
//        pageViewController.view.userInteractionEnabled = YES;
//    }
//}

#pragma mark buttonAction
- (void)tapAction{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(tapAction) object:nil];
    self.topView.hidden ? [self tapViewShow] : [self tapViewHidden];
}
- (void)tapViewShow{
    self.topView.hidden = NO;
    self.bottomView.hidden = self.topView.hidden;
    [self.topView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.right.equalTo(self.topView.superview);
        make.height.offset(NAVI_BAR_HIGHT);
        make.top.equalTo(self.topView.superview).offset(0);
    }];
    CGFloat height = TAB_BAR_ADDING + 49;
    [self.bottomView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.right.equalTo(self.bottomView.superview);
        make.height.offset(height);
        make.bottom.equalTo(self.bottomView.superview).offset(0);
    }];
    [UIView animateWithDuration:0.2 animations:^{
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        if (finished) {
            [self setNeedsStatusBarAppearanceUpdate];
        }
    }];
}
- (void)tapViewHidden{
    [self.topView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.right.equalTo(self.topView.superview);
        make.height.offset(NAVI_BAR_HIGHT);
        make.top.equalTo(self.topView.superview).offset(-NAVI_BAR_HIGHT);
    }];
    CGFloat height = TAB_BAR_ADDING + 49;
    [self.bottomView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.right.equalTo(self.bottomView.superview);
        make.height.offset(height);
        make.bottom.equalTo(self.bottomView.superview).offset(height);
    }];
    [UIView animateWithDuration:0.2 animations:^{
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        if (finished) {
            self.topView.hidden = YES;
            self.bottomView.hidden = self.topView.hidden;
            [self setNeedsStatusBarAppearanceUpdate];
        }
    }];
}
- (void)goBack{
    [self insertDataQueue];
    [self goBack:NO];
}
- (void)moreAction{
    
}
#pragma mark get

- (GKReadTopView *)topView{
    if (!_topView) {
        _topView = [GKReadTopView instanceView];
        [_topView.closeBtn addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
        [_topView.moreBtn addTarget:self action:@selector(moreAction) forControlEvents:UIControlEventTouchUpInside];
    }
    return _topView;
}
- (GKReadBottomView *)bottomView{
    if (!_bottomView) {
        _bottomView = [GKReadBottomView instanceView];
    }
    return _bottomView;
}

#pragma mark get

- (GKBookSourceInfo *)bookSource{
    if (!_bookSource) {
        _bookSource = [[GKBookSourceInfo alloc] init];
    }
    return _bookSource;
}
- (BOOL)prefersStatusBarHidden{
    return self.topView.hidden;
}

@end
